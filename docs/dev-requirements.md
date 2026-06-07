# Prérequis applicatifs — équipe backend Praxedo

Ce document liste ce que **votre application** doit respecter pour être déployable sur l'infrastructure GCP que nous avons préparée. Il est volontairement pédagogique : nous ne supposons pas de connaissance ops préalable. Si quelque chose vous semble obscur, c'est sûrement que la doc est mal faite — ouvrez une issue sur ce repo, ne devinez pas.

Les compagnons utiles à garder ouverts à côté : `docs/architecture.md` (le pourquoi), `handoff/README.md` (le pipeline GitHub Actions prêt à l'emploi côté application), `docs/runbook.md` (les opérations courantes côté infra).

---

## 0. Qui possède quoi

Avant de plonger dans le détail, cette frontière doit être claire pour tout le monde. Elle évite les conflits de déploiement et limite ce que vous avez à apprendre.

| | Plateforme (nous) | Application (vous) |
|---|---|---|
| Authentification GitHub Actions → GCP | **Workload Identity Federation** déjà en place. Pas de clé JSON, jamais. | Coller les identifiants WIF/SA dans vos variables GitHub (voir `handoff/README.md` §3). |
| Pipeline de déploiement | **Workflow GitHub Actions de référence** fourni dans `handoff/.github/workflows/deploy.yml`. À copier tel quel dans votre repo. | Le copier et le maintenir s'il évolue de votre côté (chemins, étapes maison). |
| Services Cloud Run (api + scanner) | Définition, ingress, VPC, env vars, secrets, `runAs` identity. | **Image du conteneur** + son contenu. |
| Image conteneur | Aucune. | **Construction, contenu, sécurité applicative**. |
| Schéma BDD | Aucune (vous gérez vos migrations). | Outil de migration (Flyway/Liquibase), idempotent au démarrage. |
| Secrets (valeurs) | Hébergement dans Secret Manager, montage en env var sur Cloud Run. | Consommation via `@Value` ou équivalent. Ne jamais logger une valeur. |
| Frontend (build SPA) | Bucket + LB + CDN. | Build + upload via le job `frontend` du workflow. |
| Observabilité | Logging/Monitoring managés + 3 alertes (5xx, lag scan, DLQ). | **Émettre des logs structurés** et exposer les endpoints `/actuator/health/*`. |

Règle générale : **vous ne touchez jamais à la config Cloud Run**. Pas de `--update-env-vars`, pas de `--set-secrets`, pas de `--ingress`. Le service de déploiement (`praxedo-app-deploy`) n'a d'ailleurs pas ces droits. Si vous avez besoin d'une nouvelle env var ou d'un nouveau secret, ouvrez une PR sur l'infra repo en premier, puis votre PR applicative.

---

## 1. Checklist actionnable

À cocher avant la première mise en production. Chaque item est détaillé plus bas.

- [ ] **Un seul codebase Spring Boot**, deux profils `@Profile("api")` et `@Profile("scanner")` (§2)
- [ ] **Un `Dockerfile` à la racine `backend/`**, multi-stage, image finale `-jre`, utilisateur non-root, `EXPOSE 8080` (§3)
- [ ] L'application **écoute sur `$PORT`** (Cloud Run injecte cette variable au démarrage) (§3.2)
- [ ] **Aucun état local**, aucune écriture sur disque, aucune session en mémoire (§3.3)
- [ ] Endpoints `/actuator/health/liveness` et `/actuator/health/readiness` exposés et fonctionnels (§4)
- [ ] **Variables d'environnement** : l'application lit la config depuis les variables injectées par Cloud Run, jamais depuis un fichier `application.properties` codé en dur (§5)
- [ ] **Secrets** : `SPRING_DATASOURCE_PASSWORD` et `AV_API_KEY` consommés via env var, valeur jamais loguée (§6)
- [ ] **Logs structurés JSON** sur stdout (§7)
- [ ] **Uploads volumineux** : pas de buffer en mémoire, jamais. Côté API on signe une URL, côté scanner on streame depuis GCS vers le vendor (§8)
- [ ] Migration BDD au démarrage (Flyway/Liquibase), idempotente (§9)
- [ ] Image testée localement avec `docker run -e SPRING_PROFILES_ACTIVE=api ...` avant push sur `main` (§10)

---

## 2. Spring profiles `api` et `scanner`

Rappel court (le détail vit dans `docs/architecture.md` §1.2 et `handoff/README.md` §1) : **une seule image Docker** est déployée sur **deux services Cloud Run**. Cloud Run injecte `SPRING_PROFILES_ACTIVE=api` ou `=scanner`. Spring active les bons beans à partir de cette variable.

Côté code :

```java
@RestController
@Profile("api")
public class UploadController { /* POST /api/files, GET /api/files/{id}/download */ }

@RestController
@Profile("scanner")
public class ScanPushHandler { /* POST /internal/scan, gère le push Pub/Sub */ }
```

Les beans communs (repositories JPA, services partagés, configuration globale) **ne portent pas** d'annotation `@Profile` et se chargent dans les deux.

À ne pas faire : forcer le profil dans `application.yml` ou dans le `Dockerfile`. Le profil est une responsabilité plateforme.

---

## 3. Conteneur — Dockerfile de référence

À placer à `backend/Dockerfile`. Multi-stage, image finale slim, non-root, port configurable, sans état local.

```dockerfile
# syntax=docker/dockerfile:1.7

# ---- Build stage ---------------------------------------------------------
# Le JDK n'est nécessaire que pour compiler ; il reste dans cette stage et
# ne pollue pas l'image finale.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

# Cache des dépendances Maven : le fichier pom.xml change moins souvent
# que le code, donc on l'ajoute en premier pour profiter du cache Docker.
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .
RUN ./mvnw -B -q dependency:go-offline

COPY src src
RUN ./mvnw -B -q -DskipTests package && \
    cp target/*.jar /workspace/app.jar

# ---- Runtime stage -------------------------------------------------------
# Image finale légère, uniquement le JRE. Pas de shell interactif, pas de
# package manager utile à un attaquant.
FROM eclipse-temurin:21-jre AS runtime

# Utilisateur non-root. UID/GID fixés explicitement pour éviter qu'un
# changement de base image les renumérote silencieusement.
RUN groupadd -g 10001 app && \
    useradd -u 10001 -g app -m -s /sbin/nologin app

WORKDIR /app
COPY --from=build --chown=app:app /workspace/app.jar /app/app.jar

USER 10001

# Options JVM : laisser la JVM utiliser ~75% de la RAM disponible du
# container (sinon elle se base sur la RAM hôte et OOMKill).
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Port informatif. Cloud Run écoute la valeur de l'env var PORT au runtime ;
# l'application doit honorer ${PORT:8080}.
EXPOSE 8080

ENTRYPOINT ["java","-jar","/app/app.jar"]
```

### 3.1 Multi-stage et non-root — pourquoi

- **Multi-stage** : l'image finale ne contient ni Maven, ni le JDK, ni les sources, ni les artefacts intermédiaires. Surface d'attaque réduite, image plus légère (~250 MB vs ~600 MB), pull Cloud Run plus rapide.
- **Non-root** : si un attaquant exploite une RCE dans l'application, il n'est pas root du conteneur. C'est une exigence des bonnes pratiques Cloud Run et c'est zéro coût à implémenter.

### 3.2 Port configurable

Cloud Run injecte la variable d'environnement `PORT` (par défaut `8080`) à chaque démarrage de conteneur. Votre application **doit écouter cette valeur**, pas un port codé en dur.

Pour Spring Boot, deux options équivalentes — choisissez celle qui colle à votre config :

```yaml
# src/main/resources/application.yml
server:
  port: ${PORT:8080}
```

ou, équivalent par variable d'environnement (déjà reconnue par Spring Boot sans config) :

```
SERVER_PORT=${PORT}
```

Si vous codez en dur `server.port: 8080`, ça marchera *aujourd'hui*, mais ça casse silencieusement le jour où la plateforme déplace le port — ne le faites pas.

### 3.3 Sans état local

Vos conteneurs sont **éphémères** : Cloud Run en lance, en arrête, en duplique à volonté pour absorber la charge. Concrètement :

- **Pas d'écriture sur le filesystem** sauf `/tmp` (et même là, en dernier recours pour des fichiers transitoires de très petite taille, sinon `gettempdir` est rapidement saturé). La file system est en lecture seule en dehors de `/tmp`.
- **Pas de session HTTP en mémoire**. Si vous avez besoin d'état partagé, stockez-le dans Cloud SQL. Pour du cache lecture, accepter un cache local *par instance* est OK si vous tolérez l'incohérence (sinon : pas de cache, ou Memorystore plus tard).
- **Pas de file-uploads stockés localement**. Voir §8.

---

## 4. Endpoints de santé

L'infra ne câble pas encore de liveness/readiness probes côté Cloud Run, mais les endpoints **doivent exister** dès le premier déploiement pour qu'on puisse les câbler sans toucher au code.

Ajouter Spring Boot Actuator (dépendance) et exposer :

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health
      base-path: /actuator
  endpoint:
    health:
      probes:
        enabled: true
      show-details: never  # ne jamais exposer le détail des dépendances aux callers
```

Cela publie automatiquement :

- `GET /actuator/health/liveness` → l'application répond, la JVM n'est pas dans un état cassé. Doit revenir `UP` même si la BDD est down.
- `GET /actuator/health/readiness` → l'application peut servir des requêtes. Doit revenir `OUT_OF_SERVICE` tant que la pool BDD ou la connexion à Pub/Sub n'est pas prête.

`show-details: never` est important : ces endpoints sont accessibles via le service Cloud Run, on ne fuit aucune info sur la topologie interne en cas de check par erreur depuis l'extérieur.

---

## 5. Configuration par variables d'environnement

Tout ce que votre code lit depuis l'environnement est injecté par Cloud Run, configuré côté Terraform dans `terraform/modules/compute/`. Vous ne les déclarez **nulle part** dans le repo applicatif (pas dans `application.yml`, pas dans des `.env`).

Variables fournies aux deux services :

| Variable | Origine | Profil(s) qui doivent l'utiliser |
|---|---|---|
| `PORT` | Cloud Run runtime | les deux |
| `SPRING_PROFILES_ACTIVE` | Terraform (`api` ou `scanner`) | les deux |
| `SPRING_DATASOURCE_URL` | Terraform (IP privée Cloud SQL) | les deux |
| `SPRING_DATASOURCE_USERNAME` | Terraform | les deux |
| `SPRING_DATASOURCE_PASSWORD` | Secret Manager → Cloud Run | les deux |
| `QUARANTINE_BUCKET` | Terraform (nom du bucket) | les deux |
| `CLEAN_BUCKET` | Terraform (nom du bucket) | les deux |
| `AV_API_KEY` | Secret Manager → Cloud Run | **scanner uniquement** |

Côté Spring, `SPRING_DATASOURCE_*` est consommé automatiquement par autoconfigure. Pour les autres :

```java
@Component
public class GcsConfig {
    @Value("${QUARANTINE_BUCKET}") public String quarantineBucket;
    @Value("${CLEAN_BUCKET}")      public String cleanBucket;
}
```

Pour ajouter une nouvelle variable : c'est une modification d'infra, donc une PR sur le repo infra qui ajoute l'env block dans `terraform/modules/compute/main.tf`. Vous ne pouvez pas l'ajouter depuis votre pipeline (et c'est volontaire — la divergence de config entre le code et l'infra est l'une des sources de bugs les plus longues à diagnostiquer).

---

## 6. Secrets via Secret Manager

Les secrets sont stockés dans GCP Secret Manager (versionnés, IAM-protégés, audit log). Cloud Run les **monte comme des variables d'environnement** au démarrage du conteneur — pour votre code, c'est juste un `@Value("${AV_API_KEY}")`.

Ce qui vous concerne :

- **Jamais de valeur de secret dans le code**, dans un `application.yml`, dans un commit, dans un log. Pas de fallback en dur "au cas où".
- **Jamais de log de la valeur**. Spring Boot Actuator a un endpoint `/env` qui peut tout déballer ; on l'a désactivé en §4 (`exposure.include: health`). Si vous ajoutez d'autres endpoints Actuator, vérifiez qu'aucun ne fuit la config.
- **Rotation** : un nouveau secret = nouvelle version Secret Manager côté infra + redéploiement de l'app pour qu'elle relise la valeur. Vous ne déclenchez pas la rotation, vous redéployez quand on vous le signale.

Si vous avez besoin d'un nouveau secret (nouvelle intégration), même processus que pour les env vars : PR infra d'abord (ajoute le secret + le mount), PR app ensuite.

---

## 7. Logs structurés JSON

Cloud Logging parse automatiquement les lignes JSON émises sur `stdout`. Avec un log JSON, vous obtenez des champs requêtables (`severity`, `httpRequest`, `trace`, vos propres `labels`) plutôt qu'un blob texte ingrat à `grep`.

Spring Boot 3.4+ propose une intégration native :

```yaml
logging:
  structured:
    format:
      console: gcp
  level:
    root: INFO
    com.praxedo: DEBUG  # à ajuster en prod
```

Avant Spring Boot 3.4, ajoutez un `logback-spring.xml` qui produit du JSON sur stdout (par ex. `logstash-logback-encoder` ou la config GCP officielle). N'utilisez **pas** d'appender fichier — voir §3.3 sur l'absence d'état local.

Bonnes pratiques côté code :

- Logger l'**identifiant du fichier** (DB id, object name) à chaque étape du pipeline de scan. Permet de retracer un parcours dans Cloud Logging avec un seul filtre.
- Ne **jamais logger** : valeur d'un secret, contenu d'un fichier client, URL signée complète (l'URL contient le token).
- Logger les **erreurs HTTP vers le vendor AV** avec le code status et la durée, pas le payload de retour.

---

## 8. Uploads volumineux — direct-to-GCS

Le point qui peut surprendre : **votre conteneur API ne reçoit jamais les bytes du fichier**. Cloud Run a une limite à 32 MiB par requête, donc faire transiter 500 MB par votre service est physiquement impossible et de toute façon une mauvaise idée (CPU, mémoire, latence).

### 8.1 Côté API — `POST /api/files`

1. Le client appelle `POST /api/files` avec les **métadonnées** uniquement (nom, taille, content-type).
2. L'API crée une ligne en DB (`status = PENDING_UPLOAD`).
3. L'API mint une **URL signée V4** *resumable upload* sur le bucket `quarantine` (TTL 15 min, content-type verrouillé sur la valeur déclarée).
4. L'API renvoie l'URL signée au client. Fin de la requête : la requête côté Cloud Run reste très petite.
5. Le **navigateur** uploade directement vers GCS, par chunks, avec reprise sur erreur.

Le signing utilise le mécanisme self-impersonation `signBlob` sur la SA api (la liaison IAM `roles/iam.serviceAccountTokenCreator` est déjà en place). Côté code, la bibliothèque `google-cloud-storage` gère ça :

```java
BlobInfo blobInfo = BlobInfo.newBuilder(quarantineBucket, objectName)
    .setContentType(declaredContentType)
    .build();

URL url = storage.signUrl(
    blobInfo,
    15, TimeUnit.MINUTES,
    Storage.SignUrlOption.withV4Signature(),
    Storage.SignUrlOption.httpMethod(HttpMethod.PUT),
    Storage.SignUrlOption.withContentType());
```

### 8.2 Côté scanner — lecture depuis quarantine vers le vendor AV

Le scanner reçoit un push Pub/Sub (`POST /internal/scan`) avec `{bucket, object, generation}`. Il doit :

1. Ouvrir un **stream** depuis l'objet GCS (`storage.reader()`).
2. Le passer **en streaming** au vendor AV (la plupart des vendors acceptent un PUT chunked ou une URL signée à pull). **Ne jamais charger le fichier en mémoire ni sur disque**, même si la file fait 1 MB — au moins une fois par mois quelqu'un uploade un fichier 500x plus gros que vos tests.
3. Sur verdict `CLEAN` : `copy(quarantine → clean)`, `delete(quarantine)`, flip BDD `status = CLEAN`.
4. Sur verdict `INFECTED` : `delete(quarantine)`, flip BDD `status = INFECTED`.
5. Sur 5xx vendor ou timeout : retourner un statut HTTP non-2xx au push Pub/Sub. Pub/Sub retentera avec backoff (configuré côté infra : 10s → 600s, 6 essais, puis DLQ).

### 8.3 Idempotence

Le scanner **doit être idempotent** sur la clé `(bucket, object, generation)`. Pub/Sub peut livrer un message plusieurs fois (at-least-once). Pattern recommandé : verrou applicatif PostgreSQL (`pg_advisory_xact_lock`) sur un hash de la clé au début du traitement, et vérification que la BDD n'est pas déjà en `CLEAN` ou `INFECTED` avant d'appeler le vendor.

### 8.4 Téléchargement

`GET /api/files/{id}/download` côté API : vérifie en DB que `status = CLEAN`, puis mint une URL signée V4 **sur le bucket `clean`** (TTL 5 min) et la retourne au client. Le navigateur télécharge directement depuis GCS. L'API SA n'a aucun droit en lecture sur `quarantine` — c'est l'invariant §2.3 décrit dans l'architecture, et c'est ce qui rend impossible de servir par erreur un fichier non scanné même en cas de bug applicatif.

---

## 9. Migrations BDD

Vous gérez le schéma. Outil au choix (Flyway / Liquibase). Contraintes :

- **Idempotent au démarrage** : les migrations tournent au boot de chaque instance, sans casser si elles ont déjà été appliquées.
- **Backward-compatible sur deux releases** : Cloud Run roule des revisions côte à côte pendant les déploiements. Pendant cette fenêtre, deux versions du code parlent à la même BDD. Pas de `DROP COLUMN` dans la même PR que celle qui arrête de l'utiliser ; faire ça en deux PRs successives.
- **Pas de gros refactor de données au boot**. Si une migration prend plus de 30s, c'est un job ad-hoc à exécuter manuellement et à documenter dans le runbook.

La connexion BDD passe par l'IP privée Cloud SQL via le VPC connector Cloud Run ; rien à configurer côté code au-delà des `SPRING_DATASOURCE_*`.

---

## 10. Vérification locale avant push

Avant le premier `git push`, validez que l'image fonctionne en isolation :

```sh
# Build
docker build -t praxedo-app:local backend/

# Vérifier l'utilisateur non-root
docker run --rm praxedo-app:local id
# attendu : uid=10001(app) gid=10001(app)

# Lancer le profil api
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e SPRING_PROFILES_ACTIVE=api \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/praxedo \
  -e SPRING_DATASOURCE_USERNAME=praxedo_app \
  -e SPRING_DATASOURCE_PASSWORD=local \
  -e QUARANTINE_BUCKET=praxedo-local-quarantine \
  -e CLEAN_BUCKET=praxedo-local-clean \
  praxedo-app:local

# Dans un autre terminal
curl -s localhost:8080/actuator/health/liveness   # → {"status":"UP"}
curl -s localhost:8080/actuator/health/readiness  # → {"status":"UP"} si DB joignable
```

Si tout passe en local avec ces commandes, la même image tournera sur Cloud Run. La seule différence est l'origine des env vars (Cloud Run les injecte depuis Secret Manager pour les secrets).

---

## 11. Quand demander de l'aide

Trois cas courants où ouvrir une issue (ou un message direct) sur le repo infra plutôt que de bricoler :

1. Vous avez besoin d'une nouvelle variable d'environnement, d'un nouveau secret, d'un nouveau bucket, d'un nouveau topic Pub/Sub.
2. Une revision Cloud Run échoue avec une erreur que vous n'arrivez pas à reproduire localement.
3. Vous voulez ajouter une dépendance entre votre app et un service GCP qu'on n'a pas listé ici.

Tout ce qui touche au runtime Cloud Run, à l'IAM, ou à un service GCP autre que ceux listés dans §5 est une modification d'infra.
