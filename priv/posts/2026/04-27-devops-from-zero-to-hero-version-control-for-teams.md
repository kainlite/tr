%{
  title: "DevOps from Zero to Hero: Version Control for Teams",
  author: "Gabriel Garrido",
  description: "We will explore branching strategies, pull request best practices, conventional commits, and how to set up protected branches for team collaboration...",
  tags: ~w(devops git github beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article 3 of the DevOps from Zero to Hero series. Now it is time to talk about one of the most critical tools in any engineering team: version control for teams.

<br />

If you are working alone, you can get away with committing directly to main. But the moment a second person touches the same codebase, you need structure, conventions, and guardrails to avoid stepping on each other's toes. In this article we will cover branching strategies, pull requests, conventional commits, protected branches, and merge strategies.

<br />

##### **Why Version Control Matters in DevOps**
Version control is the foundation for everything you will build in DevOps:

<br />

> * **Collaboration** Multiple people can work on the same codebase simultaneously without overwriting each other's changes
> * **Auditability** Every change is recorded with a timestamp, author, and message. You can trace exactly what changed and who changed it
> * **Rollback** Made a bad deployment? Revert to a previous known-good state in seconds
> * **Automation** CI/CD pipelines trigger based on Git events. Without version control, you cannot automate builds, tests, or deployments
> * **Code review** Pull requests create a structured process for reviewing changes before they reach production

<br />

##### **Branching Strategies**
A branching strategy defines how your team uses branches to develop, test, and release software. Let's look at the three most common ones.

<br />

**Trunk-Based Development**

Everyone commits to a single branch (`main`). Feature branches are short-lived, lasting no more than a day or two.

<br />

```plaintext
main ─────●─────●─────●─────●─────●─────●─────
            \       /   \     /
feature-a    ●───●     feature-b
```

<br />

> * **Short-lived branches** Features are broken into small pieces merged within a day or two
> * **Feature flags** Incomplete features are hidden behind flags so they can be merged safely
> * **Continuous integration** Everyone integrates frequently, reducing merge conflicts

<br />

This is the strategy I recommend for most teams. Companies like Google and Netflix use it at scale.

<br />

**GitFlow**

Uses multiple long-lived branches: `main`, `develop`, `feature/*`, `release/*`, and `hotfix/*`. Designed for teams with scheduled releases.

<br />

```plaintext
main     ─────●───────────────────●──────────────
               \                 /
develop   ──●───●───●───●───●───●───●───●────────
              \   /       \       /
feature-a      ●──●        release/1.0
```

<br />

Good for versioned software (libraries, mobile apps), but adds unnecessary complexity for web applications deployed continuously.

<br />

**GitHub Flow**

Simplified workflow: `main` and short-lived feature branches. Open a PR, get a review, merge. That is it.

<br />

> * **Simple** Only two branch types: `main` and feature branches
> * **PR driven** Every change goes through a pull request
> * **Deploy from main** The main branch is always deployable

<br />

For most teams building web applications, use trunk-based development or GitHub Flow. Use GitFlow only if you genuinely need structured release cycles.

<br />

##### **Pull Requests: The Heart of Team Collaboration**
A pull request is more than a merge request. It is a conversation about the changes you are proposing. Good PRs are the single most important practice for maintaining code quality.

<br />

**What a Good PR Looks Like**

```plaintext
## What
Brief description of what this PR does.

## Why
Why is this change needed? Link to the issue or ticket.

## How
High-level overview of the approach.

## Testing
How was this tested? Include relevant test commands or screenshots.

## Checklist
- [ ] Tests pass locally
- [ ] Documentation updated if needed
- [ ] No breaking changes (or migration path documented)
```

<br />

**Review Best Practices**

> * **Be constructive** Suggest improvements, offer alternatives when you disagree
> * **Focus on what matters** Architecture and correctness over style preferences. Let the linter handle formatting
> * **Ask questions** "Could you explain why this approach was chosen?" beats "This is wrong"
> * **Review promptly** Blocked PRs kill momentum. Review within hours, not days
> * **Keep PRs small** Aim for under 400 lines. Large PRs get rubber-stamped

<br />

##### **Conventional Commits**
Conventional commits are a specification for structured commit messages that enable automated changelogs and version bumps.

<br />

**The Format**

```plaintext
<type>(<scope>): <description>

[optional body]
[optional footer(s)]
```

<br />

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `perf`.

<br />

**Examples**

```plaintext
feat(auth): add OAuth2 login with GitHub
fix(api): handle null response from payment gateway
docs(readme): update installation instructions for v2
chore(deps): bump phoenix_live_view from 1.0.0 to 1.1.0
refactor(database): extract connection pooling into separate module
ci(github-actions): add Elixir formatter check to PR workflow
feat(notifications)!: redesign notification system

BREAKING CHANGE: notification payloads now use snake_case keys
```

<br />

> * **Automated changelogs** Tools like `release-please` generate changelogs from commit history
> * **Semantic versioning** Commit type determines patch (fix), minor (feat), or major (breaking change)
> * **Readable history** `git log --oneline` becomes a clear story of what happened

<br />

##### **Protected Branches**
Protected branches prevent dangerous actions on important branches like `main`. Here is how to set them up on GitHub:

<br />

1. Go to your repository, then **Settings** > **Branches**
2. Click **Add branch protection rule**, set pattern to `main`
3. Configure the rules:

<br />

```plaintext
[x] Require a pull request before merging
    [x] Require approvals: 1
    [x] Dismiss stale approvals when new commits are pushed

[x] Require status checks to pass before merging
    [x] Require branches to be up to date before merging

[x] Do not allow force pushes
[x] Do not allow deletions
[x] Do not allow bypassing the above settings
```

<br />

You can also do this with the GitHub CLI:

```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci/tests", "ci/lint"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

<br />

**CODEOWNERS File**

Define who reviews changes to specific parts of the codebase:

```plaintext
# .github/CODEOWNERS
* @your-team/backend
/assets/ @your-team/frontend
/terraform/ @your-team/platform
/.github/workflows/ @your-team/platform @your-team/leads
```

<br />

##### **Merge Strategies**
When merging a PR on GitHub, you have three options:

<br />

**Merge Commit** preserves all individual commits plus a merge commit. Full history, but can get messy.

```bash
# * abc1234 Merge pull request #42
# |\
# | * def5678 fix: handle edge case
# | * ghi9012 feat: add JWT validation
# |/
# * mno7890 Previous commit
```

<br />

**Squash and Merge** combines all commits into one on main. Clean, linear history.

```bash
# * abc1234 feat(auth): add JWT authentication (#42)
# * mno7890 Previous commit
```

<br />

**Rebase and Merge** replays individual commits on top of main. Linear history with full commit detail.

```bash
# * abc1234 fix: handle edge case
# * def5678 feat: add JWT validation
# * ghi9012 feat: add login endpoint
# * mno7890 Previous commit
```

<br />

For most teams, **squash and merge** is the sweet spot. It keeps main clean and encourages small, focused PRs.

<br />

##### **Practical Tips**

**Meaningful branch names** with consistent prefixes:

```plaintext
feature/add-oauth-login
fix/null-pointer-in-payment
chore/upgrade-elixir-to-1.17
docs/update-api-reference
```

<br />

**Atomic commits** where each commit represents one logical change:

```bash
git add lib/auth/session.ex
git commit -m "fix(auth): prevent session fixation on password reset"

git add test/auth/session_test.exs
git commit -m "test(auth): add regression test for session fixation"
```

<br />

**Rebase before merging** to keep your branch up to date:

```bash
git fetch origin
git rebase origin/main
# Use --force-with-lease instead of --force (safer)
git push --force-with-lease origin feature/add-auth
```

<br />

**Clean up merged branches** to avoid clutter:

```bash
git fetch --prune
git branch --merged main | grep -v "main" | xargs git branch -d
```

<br />

##### **Closing notes**
Version control is the backbone of how teams collaborate and how code reaches production safely. Getting your Git workflow right early saves enormous amounts of pain down the road.

<br />

The key takeaways: use trunk-based development or GitHub Flow, keep PRs small, adopt conventional commits, protect your main branch, and use squash merges. Start simple, add complexity only when you need it.

<br />

In the next article, we will dive into CI/CD pipelines. Stay tuned!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and examples in the [repository here](https://github.com/kainlite/tr).

<br />

---lang---
%{
  title: "DevOps desde Cero: Control de Versiones para Equipos",
  author: "Gabriel Garrido",
  description: "Vamos a explorar estrategias de branching, buenas practicas de pull requests, commits convencionales y como configurar branches protegidos para colaborar en equipo...",
  tags: ~w(devops git github beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al articulo 3 de la serie DevOps desde Cero. Ahora es momento de hablar sobre una de las herramientas mas criticas en cualquier equipo de ingenieria: el control de versiones para equipos.

<br />

Si estas trabajando solo, podes salir adelante commiteando directamente a main. Pero en el momento en que una segunda persona toca el mismo codebase, necesitas estructura, convenciones y barreras de seguridad. En este articulo vamos a cubrir estrategias de branching, pull requests, commits convencionales, branches protegidos y estrategias de merge.

<br />

##### **Por que importa el control de versiones en DevOps**
El control de versiones es la base para todo lo que vas a construir en DevOps:

<br />

> * **Colaboracion** Multiples personas pueden trabajar en el mismo codebase simultaneamente sin sobreescribir los cambios del otro
> * **Auditabilidad** Cada cambio queda registrado con timestamp, autor y mensaje. Podes rastrear exactamente que cambio y quien lo cambio
> * **Rollback** Hiciste un deploy malo? Volve a un estado anterior conocido en segundos
> * **Automatizacion** Los pipelines de CI/CD se disparan basandose en eventos de Git. Sin control de versiones, no podes automatizar builds, tests ni deployments
> * **Code review** Los pull requests crean un proceso estructurado para revisar cambios antes de que lleguen a produccion

<br />

##### **Estrategias de Branching**
Una estrategia de branching define como tu equipo usa branches para desarrollar, testear y liberar software. Veamos las tres mas comunes.

<br />

**Trunk-Based Development**

Todos commitean a un solo branch (`main`). Los feature branches son de vida corta, duran no mas de uno o dos dias.

<br />

```plaintext
main ─────●─────●─────●─────●─────●─────●─────
            \       /   \     /
feature-a    ●───●     feature-b
```

<br />

> * **Branches de vida corta** Las features se dividen en pedazos chicos que se mergean en un dia o dos
> * **Feature flags** Las features incompletas se esconden detras de flags para que se puedan mergear de forma segura
> * **Integracion continua** Todos integran frecuentemente, reduciendo conflictos de merge

<br />

Esta es la estrategia que recomiendo para la mayoria de los equipos. Empresas como Google y Netflix la usan a escala.

<br />

**GitFlow**

Usa multiples branches de vida larga: `main`, `develop`, `feature/*`, `release/*` y `hotfix/*`. Disenado para equipos con releases programados.

<br />

```plaintext
main     ─────●───────────────────●──────────────
               \                 /
develop   ──●───●───●───●───●───●───●───●────────
              \   /       \       /
feature-a      ●──●        release/1.0
```

<br />

Bueno para software versionado (librerias, apps moviles), pero agrega complejidad innecesaria para aplicaciones web que se deployean continuamente.

<br />

**GitHub Flow**

Workflow simplificado: `main` y feature branches de vida corta. Abris un PR, conseguis un review, mergeas. Eso es todo.

<br />

> * **Simple** Solo dos tipos de branches: `main` y feature branches
> * **Orientado a PRs** Cada cambio pasa por un pull request
> * **Deploy desde main** El branch main siempre esta deployable

<br />

Para la mayoria de los equipos que construyen aplicaciones web, usa trunk-based development o GitHub Flow. Usa GitFlow solo si genuinamente necesitas ciclos de release estructurados.

<br />

##### **Pull Requests: El Corazon de la Colaboracion**
Un pull request es mas que una solicitud de merge. Es una conversacion sobre los cambios que estas proponiendo. Los buenos PRs son la practica mas importante para mantener la calidad del codigo.

<br />

**Como se ve un buen PR**

```plaintext
## Que
Descripcion breve de que hace este PR.

## Por que
Por que se necesita este cambio? Link al issue o ticket.

## Como
Resumen de alto nivel del enfoque.

## Testing
Como se testeo? Incluye comandos de test relevantes o screenshots.

## Checklist
- [ ] Tests pasan localmente
- [ ] Documentacion actualizada si es necesario
- [ ] Sin cambios que rompan (o ruta de migracion documentada)
```

<br />

**Mejores practicas para reviews**

> * **Se constructivo** Sugeri mejoras, ofrece alternativas cuando no estes de acuerdo
> * **Enfocate en lo importante** Arquitectura y correctitud por sobre preferencias de estilo. Deja que el linter se encargue del formateo
> * **Hace preguntas** "Podrias explicar por que se eligio este enfoque?" es mejor que "Esto esta mal"
> * **Revisa rapido** Los PRs bloqueados matan el momentum. Revisa en horas, no en dias
> * **Mantene los PRs chicos** Apunta a menos de 400 lineas. Los PRs grandes reciben aprobaciones sin revision real

<br />

##### **Commits Convencionales**
Los commits convencionales son una especificacion para mensajes de commit estructurados que habilitan changelogs automaticos y bumps de version.

<br />

**El Formato**

```plaintext
<tipo>(<scope>): <descripcion>

[cuerpo opcional]
[footer(s) opcionales]
```

<br />

Tipos comunes: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `perf`.

<br />

**Ejemplos**

```plaintext
feat(auth): add OAuth2 login with GitHub
fix(api): handle null response from payment gateway
docs(readme): update installation instructions for v2
chore(deps): bump phoenix_live_view from 1.0.0 to 1.1.0
refactor(database): extract connection pooling into separate module
ci(github-actions): add Elixir formatter check to PR workflow
feat(notifications)!: redesign notification system

BREAKING CHANGE: notification payloads now use snake_case keys
```

<br />

> * **Changelogs automaticos** Herramientas como `release-please` generan changelogs desde el historial de commits
> * **Versionado semantico** El tipo del commit determina patch (fix), minor (feat) o major (breaking change)
> * **Historial legible** `git log --oneline` se convierte en una historia clara de que paso

<br />

##### **Branches Protegidos**
Los branches protegidos previenen acciones peligrosas en branches importantes como `main`. Asi se configuran en GitHub:

<br />

1. Anda a tu repositorio, despues **Settings** > **Branches**
2. Hace click en **Add branch protection rule**, configura el patron a `main`
3. Configura las reglas:

<br />

```plaintext
[x] Require a pull request before merging
    [x] Require approvals: 1
    [x] Dismiss stale approvals when new commits are pushed

[x] Require status checks to pass before merging
    [x] Require branches to be up to date before merging

[x] Do not allow force pushes
[x] Do not allow deletions
[x] Do not allow bypassing the above settings
```

<br />

Tambien podes hacerlo con el GitHub CLI:

```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  --method PUT \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["ci/tests", "ci/lint"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

<br />

**Archivo CODEOWNERS**

Define quien revisa cambios en partes especificas del codebase:

```plaintext
# .github/CODEOWNERS
* @tu-equipo/backend
/assets/ @tu-equipo/frontend
/terraform/ @tu-equipo/platform
/.github/workflows/ @tu-equipo/platform @tu-equipo/leads
```

<br />

##### **Estrategias de Merge**
Cuando mergeas un PR en GitHub, tenes tres opciones:

<br />

**Merge Commit** preserva todos los commits individuales mas un merge commit. Historial completo, pero puede ponerse desordenado.

```bash
# * abc1234 Merge pull request #42
# |\
# | * def5678 fix: handle edge case
# | * ghi9012 feat: add JWT validation
# |/
# * mno7890 Commit anterior
```

<br />

**Squash and Merge** combina todos los commits en uno solo en main. Historial limpio y lineal.

```bash
# * abc1234 feat(auth): add JWT authentication (#42)
# * mno7890 Commit anterior
```

<br />

**Rebase and Merge** reproduce los commits individuales encima de main. Historial lineal con todo el detalle.

```bash
# * abc1234 fix: handle edge case
# * def5678 feat: add JWT validation
# * ghi9012 feat: add login endpoint
# * mno7890 Commit anterior
```

<br />

Para la mayoria de los equipos, **squash and merge** es el punto justo. Mantiene main limpio y fomenta PRs chicos y enfocados.

<br />

##### **Tips Practicos**

**Nombres de branches significativos** con prefijos consistentes:

```plaintext
feature/add-oauth-login
fix/null-pointer-in-payment
chore/upgrade-elixir-to-1.17
docs/update-api-reference
```

<br />

**Commits atomicos** donde cada commit representa un cambio logico:

```bash
git add lib/auth/session.ex
git commit -m "fix(auth): prevent session fixation on password reset"

git add test/auth/session_test.exs
git commit -m "test(auth): add regression test for session fixation"
```

<br />

**Rebasea antes de mergear** para mantener tu branch actualizado:

```bash
git fetch origin
git rebase origin/main
# Usa --force-with-lease en vez de --force (mas seguro)
git push --force-with-lease origin feature/add-auth
```

<br />

**Limpia los branches mergeados** para evitar desorden:

```bash
git fetch --prune
git branch --merged main | grep -v "main" | xargs git branch -d
```

<br />

##### **Notas finales**
El control de versiones es la columna vertebral de como los equipos colaboran y como el codigo llega a produccion de forma segura. Tener tu workflow de Git bien configurado desde el principio te ahorra cantidades enormes de dolor a futuro.

<br />

Los puntos clave: usa trunk-based development o GitHub Flow, mantene los PRs chicos, adopta commits convencionales, protege tu branch main y usa squash merges. Empeza simple, agrega complejidad solo cuando la necesites.

<br />

En el proximo articulo, vamos a meternos de lleno en pipelines de CI/CD. Estemos atentos!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje asi se corrige.

Tambien podes ver el codigo fuente y ejemplos en el [repositorio aca](https://github.com/kainlite/tr).
