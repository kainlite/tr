%{
  title: "Git Recovery Magic: Reflog, Reset Recovery, and Cherry-Picking",
  author: "Gabriel Garrido",
  description: "We'll explore Git's safety net features: reflog for recovering lost commits, restoring deleted branches, and cherry-picking specific changes...",
  tags: ~w(git),
  published: true,
  image: "git.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will explore Git's most powerful recovery features that can save your day when things go wrong. If you've ever lost commits after a bad rebase, accidentally deleted a branch, or needed to grab just one specific commit from another branch, you know the panic. But Git never truly forgets - it's just a matter of knowing where to look.

<br />

Git's reflog is like a time machine for your repository. Every action you take is recorded, and with the right commands, you can recover almost anything. We'll also dive into cherry-picking, which lets you surgically extract specific commits and apply them wherever you need them.

<br />

By the end of this article, you'll never fear Git operations again. You'll know that whatever happens, there's almost always a way to get your work back.

<br />

##### **Understanding the Reflog**
The reflog (reference log) is Git's safety net. It records every change to HEAD and branch tips in your local repository. Think of it as Git's undo history - but way more powerful.

<br />

Let's start by looking at what's in your reflog:
```elixir
git reflog
# or for more detail
git reflog show HEAD
```

<br />

You'll see something like this:
```elixir
3f7a8b9 (HEAD -> main) HEAD@{0}: commit: Add new feature
8d4c2e1 HEAD@{1}: rebase -i (finish): returning to refs/heads/main
8d4c2e1 HEAD@{2}: rebase -i (pick): Update documentation
a5b9c3d HEAD@{3}: rebase -i (squash): Fix bug
e2f1d4c HEAD@{4}: rebase -i (start): checkout origin/main
7c9e3a2 HEAD@{5}: commit: Work in progress
```

<br />

Each entry shows:
- The commit SHA
- The reflog entry reference (HEAD@{n})
- The action that was performed
- The commit message or operation details

<br />

The beautiful thing? These entries persist for 90 days by default (30 days for unreachable commits), giving you plenty of time to recover from mistakes.

<br />

##### **Recovering from a Bad Rebase**
Let's say you're rebasing and things go horribly wrong. Maybe you accidentally dropped important commits or resolved conflicts incorrectly. Don't panic!

<br />

**Scenario: Messed up interactive rebase**
```elixir
# You did an interactive rebase
git rebase -i HEAD~5

# You accidentally deleted important commits or messed up the history
# Now your branch is broken
```

<br />

**Recovery using reflog:**
```elixir
# First, check where you were before the rebase
git reflog

# Find the entry before "rebase -i (start)"
# Let's say it's HEAD@{5}

# Option 1: Reset to before the rebase
git reset --hard HEAD@{5}

# Option 2: If you want to be more careful, create a backup branch first
git branch backup-before-reset
git reset --hard HEAD@{5}
```

<br />

**Pro tip:** Always check what you're resetting to first:
```elixir
# See what's at that reflog entry
git show HEAD@{5}

# See the full log from that point
git log HEAD@{5} --oneline -10
```

<br />

##### **Recovering Deleted Commits (After git reset)**
Accidentally ran `git reset --hard` and lost commits? They're not gone, just unreferenced. Here's how to get them back:

<br />

**Scenario: Accidental hard reset**
```elixir
# You had important work
git log --oneline
# abc123 Important feature
# def456 Critical bugfix
# ghi789 Previous work

# Then you accidentally reset
git reset --hard HEAD~2

# Oh no! Your important feature and bugfix are gone!
```

<br />

**Recovery process:**
```elixir
# Step 1: Find the lost commits in reflog
git reflog
# You'll see something like:
# ghi789 HEAD@{0}: reset: moving to HEAD~2
# abc123 HEAD@{1}: commit: Important feature
# def456 HEAD@{2}: commit: Critical bugfix

# Step 2: Recover to the lost commit
git reset --hard HEAD@{1}
# or use the SHA directly
git reset --hard abc123

# Alternative: Cherry-pick specific commits if you don't want to reset
git cherry-pick abc123
git cherry-pick def456
```

<br />

**Creating a recovery branch:**
Sometimes you want to explore the lost commits without affecting your current branch:
```elixir
# Create a new branch from the lost commit
git branch recovery-branch abc123

# Switch to it and check
git checkout recovery-branch
git log --oneline

# If everything looks good, merge it back
git checkout main
git merge recovery-branch
```

<br />

##### **Recovering Deleted Branches**
Deleted a branch by mistake? As long as it wasn't deleted on the remote and force-pushed, you can recover it locally.

<br />

**Scenario: Accidental branch deletion**
```elixir
# You had a feature branch
git branch
# * main
#   feature-awesome
#   bugfix-critical

# Accidentally deleted it
git branch -D feature-awesome
# Deleted branch feature-awesome (was 5a3f8c9).
```

<br />

**Recovery methods:**

**Method 1: If you see the SHA in the deletion message**
```elixir
# Git tells you the SHA when deleting
# Just recreate the branch from that commit
git branch feature-awesome 5a3f8c9

# Or checkout and recreate
git checkout -b feature-awesome 5a3f8c9
```

<br />

**Method 2: Using reflog to find the branch**
```elixir
# Search reflog for the branch name
git reflog show --all | grep feature-awesome

# Or look for commits from that branch
git reflog --all

# Once you find the last commit SHA
git checkout -b feature-awesome-recovered <sha>
```

<br />

**Method 3: If you recently checked out the branch**
```elixir
# Git tracks branch checkouts
git reflog | grep checkout

# You might see:
# 3d4e5f6 HEAD@{3}: checkout: moving from feature-awesome to main

# Find where you moved FROM feature-awesome
git checkout -b feature-awesome-recovered 3d4e5f6
```

<br />

##### **Cherry-Picking: Surgical Commit Extraction**
Cherry-picking lets you take specific commits from one branch and apply them to another. It's like copy-pasting commits.

<br />

**Basic cherry-pick:**
```elixir
# You're on main branch and want a specific commit from feature branch
git checkout main

# Find the commit you want
git log feature --oneline
# abc123 Add awesome feature
# def456 Fix typo
# ghi789 Update tests

# Cherry-pick the specific commit
git cherry-pick abc123

# The commit is now applied to main
```

<br />

**Cherry-picking multiple commits:**
```elixir
# Pick a range of commits
git cherry-pick abc123..def456

# Pick specific commits (not a range)
git cherry-pick abc123 def456 ghi789

# Pick the last 3 commits from another branch
git cherry-pick feature~3..feature
```

<br />

**Handling cherry-pick conflicts:**
```elixir
# Start cherry-pick
git cherry-pick abc123

# If there's a conflict
# Fix the conflicts in your editor
vim conflicted-file.txt

# Add the resolved files
git add conflicted-file.txt

# Continue the cherry-pick
git cherry-pick --continue

# Or abort if things go wrong
git cherry-pick --abort
```

<br />

**Cherry-pick options:**
```elixir
# Cherry-pick but don't commit (stage changes only)
git cherry-pick -n abc123

# Cherry-pick and edit the commit message
git cherry-pick -e abc123

# Cherry-pick and add "cherry picked from" message
git cherry-pick -x abc123

# This adds a line like:
# (cherry picked from commit abc123...)
```

<br />

##### **Advanced Reflog Techniques**

**Searching through reflog:**
```elixir
# Find all commits with specific message
git reflog --grep="feature"

# Show reflog for specific branch
git reflog show feature-branch

# Show reflog with dates
git reflog --date=relative

# Show reflog for all references
git reflog show --all
```

<br />

**Time-based recovery:**
```elixir
# See where HEAD was yesterday
git show HEAD@{yesterday}

# See where HEAD was 2 hours ago
git show HEAD@{2.hours.ago}

# Reset to where you were this morning
git reset --hard HEAD@{10.hours.ago}

# See what main branch looked like last week
git show main@{1.week.ago}
```

<br />

**Cleaning up after recovery:**
```elixir
# After recovering commits, clean up duplicate branches
git branch --merged | grep -v main | xargs git branch -d

# Garbage collect to clean up unreferenced objects (careful!)
git gc --prune=now

# See what would be cleaned up
git fsck --unreachable
```

<br />

##### **Real-World Recovery Scenarios**

**Scenario 1: Lost work after force push**
```elixir
# Someone force-pushed to the remote
git pull
# Your local work seems gone!

# Find your work in reflog
git reflog
# Find your last commit before pull

# Create a branch from your work
git branch my-saved-work HEAD@{1}

# Now merge or rebase your work back
git rebase origin/main my-saved-work
```

<br />

**Scenario 2: Recovering a specific file version**
```elixir
# You need a file from a deleted commit
git reflog
# Find the commit: abc123

# Get the file without checking out the commit
git show abc123:path/to/file.js > recovered-file.js

# Or restore it directly
git checkout abc123 -- path/to/file.js
```

<br />

**Scenario 3: Undo last few operations**
```elixir
# You did several operations and want to undo them all
git reflog
# See your last "safe" point

# Create a backup of current state
git branch backup-current

# Reset to the safe point
git reset --hard HEAD@{10}
```

<br />

##### **Best Practices and Safety Tips**

**1. Always create backup branches before dangerous operations:**
```elixir
# Before rebasing
git branch backup-before-rebase

# Before reset
git branch backup-before-reset

# Before merge
git branch backup-before-merge
```

<br />

**2. Use git stash for temporary safety:**
```elixir
# Save current work before experimenting
git stash save "Before trying dangerous operation"

# Do your dangerous operation
git rebase -i HEAD~10

# If things go wrong, reset and restore stash
git reset --hard ORIG_HEAD
git stash pop
```

<br />

**3. Configure reflog to keep entries longer:**
```elixir
# Keep reflog entries for 180 days
git config gc.reflogExpire 180.days

# Keep unreachable objects for 60 days
git config gc.reflogExpireUnreachable 60.days
```

<br />

**4. Learn to read reflog patterns:**
- `HEAD@{n}`: The nth previous position of HEAD
- `branch@{n}`: The nth previous position of a specific branch
- `@{-n}`: The nth branch checked out before current
- `@{upstream}`: The upstream branch

<br />

##### **Cherry-Pick vs Merge vs Rebase**
When should you use cherry-pick instead of merge or rebase?

<br />

**Use cherry-pick when:**
- You need specific commits, not entire branches
- Backporting fixes to release branches
- Moving a commit to the correct branch
- Extracting commits from abandoned branches

<br />

**Use merge when:**
- Combining entire feature branches
- Preserving complete history
- Working with shared branches

<br />

**Use rebase when:**
- Cleaning up local history before pushing
- Updating feature branch with main
- Maintaining linear history

<br />

##### **Troubleshooting Common Issues**

**"fatal: ambiguous argument 'HEAD@{n}'"**
```elixir
# Escape the braces in some shells
git reset --hard 'HEAD@{1}'
# or
git reset --hard HEAD@\{1\}
```

<br />

**"warning: reflog of 'branch' references pruned commits"**
```elixir
# The commits are still there, just unreachable
# Find them with
git fsck --unreachable | grep commit

# Recover specific unreachable commit
git show <unreachable-sha>
git branch recovered <unreachable-sha>
```

<br />

**"error: could not apply abc123"**
```elixir
# Cherry-pick conflict
# See what's conflicting
git status

# See the differences
git diff

# Resolve and continue, or abort
git cherry-pick --abort
```

<br />

##### **Conclusion**
Git's reflog is your safety net, and cherry-pick is your precision tool. Together, they make Git much less scary. Remember:

<br />

> * Git rarely truly deletes anything immediately
> * The reflog is your time machine - use it!
> * Cherry-pick when you need surgical precision
> * Always create backup branches before risky operations
> * When in doubt, check the reflog

<br />

The next time you think you've lost work in Git, don't panic. Take a breath, check the reflog, and remember that your commits are probably just a few commands away from recovery. Git has your back, you just need to know how to ask for help!

<br />

Practice these commands in a test repository until they become second nature. The confidence of knowing you can recover from almost any Git mistake is invaluable.

<br />

Until next time, may your commits be safe and your reflog always accessible!

---lang---
%{
  title: "Magia de Recuperación en Git: Reflog, Recuperación de Reset y Cherry-Picking",
  author: "Gabriel Garrido",
  description: "Exploraremos las características de seguridad de Git: reflog para recuperar commits perdidos, restaurar branches eliminados y cherry-picking de cambios específicos...",
  tags: ~w(git),
  published: true,
  image: "git.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo vamos a explorar las características de recuperación más poderosas de Git que pueden salvarte el día cuando las cosas salen mal. Si alguna vez perdiste commits después de un rebase mal hecho, borraste accidentalmente un branch, o necesitaste agarrar solo un commit específico de otro branch, conocés el pánico. Pero Git nunca olvida realmente - es solo cuestión de saber dónde buscar.

<br />

El reflog de Git es como una máquina del tiempo para tu repositorio. Cada acción que hacés se registra, y con los comandos correctos, podés recuperar casi cualquier cosa. También vamos a profundizar en cherry-picking, que te permite extraer quirúrgicamente commits específicos y aplicarlos donde los necesites.

<br />

Al final de este artículo, nunca más vas a temer a las operaciones de Git. Vas a saber que pase lo que pase, casi siempre hay una forma de recuperar tu trabajo.

<br />

##### **Entendiendo el Reflog**
El reflog (registro de referencias) es la red de seguridad de Git. Registra cada cambio en HEAD y las puntas de los branches en tu repositorio local. Pensalo como el historial de deshacer de Git - pero mucho más poderoso.

<br />

Empecemos viendo qué hay en tu reflog:
```elixir
git reflog
# o para más detalle
git reflog show HEAD
```

<br />

Vas a ver algo así:
```elixir
3f7a8b9 (HEAD -> main) HEAD@{0}: commit: Agregar nueva función
8d4c2e1 HEAD@{1}: rebase -i (finish): returning to refs/heads/main
8d4c2e1 HEAD@{2}: rebase -i (pick): Actualizar documentación
a5b9c3d HEAD@{3}: rebase -i (squash): Arreglar bug
e2f1d4c HEAD@{4}: rebase -i (start): checkout origin/main
7c9e3a2 HEAD@{5}: commit: Trabajo en progreso
```

<br />

Cada entrada muestra:
- El SHA del commit
- La referencia de entrada del reflog (HEAD@{n})
- La acción que se realizó
- El mensaje del commit o detalles de la operación

<br />

¿Lo hermoso? Estas entradas persisten por 90 días por defecto (30 días para commits inalcanzables), dándote mucho tiempo para recuperarte de errores.

<br />

##### **Recuperándose de un Rebase Malo**
Digamos que estás haciendo rebase y las cosas salen horriblemente mal. Tal vez borraste accidentalmente commits importantes o resolviste conflictos incorrectamente. ¡No entres en pánico!

<br />

**Escenario: Rebase interactivo arruinado**
```elixir
# Hiciste un rebase interactivo
git rebase -i HEAD~5

# Accidentalmente borraste commits importantes o arruinaste el historial
# Ahora tu branch está roto
```

<br />

**Recuperación usando reflog:**
```elixir
# Primero, verificá dónde estabas antes del rebase
git reflog

# Encontrá la entrada antes de "rebase -i (start)"
# Digamos que es HEAD@{5}

# Opción 1: Reset al estado antes del rebase
git reset --hard HEAD@{5}

# Opción 2: Si querés ser más cuidadoso, creá un branch de backup primero
git branch backup-antes-reset
git reset --hard HEAD@{5}
```

<br />

**Tip pro:** Siempre verificá a qué estás haciendo reset primero:
```elixir
# Ver qué hay en esa entrada del reflog
git show HEAD@{5}

# Ver el log completo desde ese punto
git log HEAD@{5} --oneline -10
```

<br />

##### **Recuperando Commits Borrados (Después de git reset)**
¿Accidentalmente ejecutaste `git reset --hard` y perdiste commits? No se fueron, solo están sin referencia. Así es como recuperarlos:

<br />

**Escenario: Reset hard accidental**
```elixir
# Tenías trabajo importante
git log --oneline
# abc123 Función importante
# def456 Bugfix crítico
# ghi789 Trabajo previo

# Luego accidentalmente hiciste reset
git reset --hard HEAD~2

# ¡Oh no! ¡Tu función importante y bugfix se fueron!
```

<br />

**Proceso de recuperación:**
```elixir
# Paso 1: Encontrar los commits perdidos en reflog
git reflog
# Vas a ver algo como:
# ghi789 HEAD@{0}: reset: moving to HEAD~2
# abc123 HEAD@{1}: commit: Función importante
# def456 HEAD@{2}: commit: Bugfix crítico

# Paso 2: Recuperar al commit perdido
git reset --hard HEAD@{1}
# o usar el SHA directamente
git reset --hard abc123

# Alternativa: Cherry-pick commits específicos si no querés hacer reset
git cherry-pick abc123
git cherry-pick def456
```

<br />

**Creando un branch de recuperación:**
A veces querés explorar los commits perdidos sin afectar tu branch actual:
```elixir
# Crear un nuevo branch desde el commit perdido
git branch branch-recuperacion abc123

# Cambiar a él y verificar
git checkout branch-recuperacion
git log --oneline

# Si todo se ve bien, merge de vuelta
git checkout main
git merge branch-recuperacion
```

<br />

##### **Recuperando Branches Eliminados**
¿Borraste un branch por error? Mientras no haya sido borrado en el remoto y force-pusheado, podés recuperarlo localmente.

<br />

**Escenario: Eliminación accidental de branch**
```elixir
# Tenías un feature branch
git branch
# * main
#   feature-increible
#   bugfix-critico

# Accidentalmente lo borraste
git branch -D feature-increible
# Deleted branch feature-increible (was 5a3f8c9).
```

<br />

**Métodos de recuperación:**

**Método 1: Si ves el SHA en el mensaje de eliminación**
```elixir
# Git te dice el SHA al borrar
# Solo recreá el branch desde ese commit
git branch feature-increible 5a3f8c9

# O checkout y recrear
git checkout -b feature-increible 5a3f8c9
```

<br />

**Método 2: Usando reflog para encontrar el branch**
```elixir
# Buscar en reflog el nombre del branch
git reflog show --all | grep feature-increible

# O buscar commits de ese branch
git reflog --all

# Una vez que encuentres el último SHA del commit
git checkout -b feature-increible-recuperado <sha>
```

<br />

**Método 3: Si recientemente hiciste checkout del branch**
```elixir
# Git rastrea los checkouts de branches
git reflog | grep checkout

# Podrías ver:
# 3d4e5f6 HEAD@{3}: checkout: moving from feature-increible to main

# Encontrá desde dónde te moviste DE feature-increible
git checkout -b feature-increible-recuperado 3d4e5f6
```

<br />

##### **Cherry-Picking: Extracción Quirúrgica de Commits**
Cherry-picking te permite tomar commits específicos de un branch y aplicarlos a otro. Es como copiar y pegar commits.

<br />

**Cherry-pick básico:**
```elixir
# Estás en el branch main y querés un commit específico del branch feature
git checkout main

# Encontrar el commit que querés
git log feature --oneline
# abc123 Agregar función increíble
# def456 Arreglar typo
# ghi789 Actualizar tests

# Cherry-pick el commit específico
git cherry-pick abc123

# El commit ahora está aplicado en main
```

<br />

**Cherry-picking múltiples commits:**
```elixir
# Elegir un rango de commits
git cherry-pick abc123..def456

# Elegir commits específicos (no un rango)
git cherry-pick abc123 def456 ghi789

# Elegir los últimos 3 commits de otro branch
git cherry-pick feature~3..feature
```

<br />

**Manejando conflictos en cherry-pick:**
```elixir
# Iniciar cherry-pick
git cherry-pick abc123

# Si hay un conflicto
# Arreglar los conflictos en tu editor
vim archivo-conflictivo.txt

# Agregar los archivos resueltos
git add archivo-conflictivo.txt

# Continuar el cherry-pick
git cherry-pick --continue

# O abortar si las cosas salen mal
git cherry-pick --abort
```

<br />

**Opciones de cherry-pick:**
```elixir
# Cherry-pick pero no commitear (solo stagear cambios)
git cherry-pick -n abc123

# Cherry-pick y editar el mensaje del commit
git cherry-pick -e abc123

# Cherry-pick y agregar mensaje "cherry picked from"
git cherry-pick -x abc123

# Esto agrega una línea como:
# (cherry picked from commit abc123...)
```

<br />

##### **Técnicas Avanzadas de Reflog**

**Buscando en el reflog:**
```elixir
# Encontrar todos los commits con mensaje específico
git reflog --grep="feature"

# Mostrar reflog para branch específico
git reflog show feature-branch

# Mostrar reflog con fechas
git reflog --date=relative

# Mostrar reflog para todas las referencias
git reflog show --all
```

<br />

**Recuperación basada en tiempo:**
```elixir
# Ver dónde estaba HEAD ayer
git show HEAD@{yesterday}

# Ver dónde estaba HEAD hace 2 horas
git show HEAD@{2.hours.ago}

# Reset a donde estabas esta mañana
git reset --hard HEAD@{10.hours.ago}

# Ver cómo se veía main la semana pasada
git show main@{1.week.ago}
```

<br />

**Limpiando después de recuperar:**
```elixir
# Después de recuperar commits, limpiar branches duplicados
git branch --merged | grep -v main | xargs git branch -d

# Recolección de basura para limpiar objetos sin referencia (¡cuidado!)
git gc --prune=now

# Ver qué se limpiaría
git fsck --unreachable
```

<br />

##### **Escenarios de Recuperación del Mundo Real**

**Escenario 1: Trabajo perdido después de force push**
```elixir
# Alguien hizo force-push al remoto
git pull
# ¡Tu trabajo local parece haberse ido!

# Encontrar tu trabajo en reflog
git reflog
# Encontrar tu último commit antes del pull

# Crear un branch desde tu trabajo
git branch mi-trabajo-salvado HEAD@{1}

# Ahora merge o rebase tu trabajo de vuelta
git rebase origin/main mi-trabajo-salvado
```

<br />

**Escenario 2: Recuperando una versión específica de archivo**
```elixir
# Necesitás un archivo de un commit borrado
git reflog
# Encontrar el commit: abc123

# Obtener el archivo sin hacer checkout del commit
git show abc123:ruta/al/archivo.js > archivo-recuperado.js

# O restaurarlo directamente
git checkout abc123 -- ruta/al/archivo.js
```

<br />

**Escenario 3: Deshacer las últimas operaciones**
```elixir
# Hiciste varias operaciones y querés deshacerlas todas
git reflog
# Ver tu último punto "seguro"

# Crear un backup del estado actual
git branch backup-actual

# Reset al punto seguro
git reset --hard HEAD@{10}
```

<br />

##### **Mejores Prácticas y Tips de Seguridad**

**1. Siempre crear branches de backup antes de operaciones peligrosas:**
```elixir
# Antes de rebase
git branch backup-antes-rebase

# Antes de reset
git branch backup-antes-reset

# Antes de merge
git branch backup-antes-merge
```

<br />

**2. Usar git stash para seguridad temporal:**
```elixir
# Guardar trabajo actual antes de experimentar
git stash save "Antes de intentar operación peligrosa"

# Hacer tu operación peligrosa
git rebase -i HEAD~10

# Si las cosas salen mal, reset y restaurar stash
git reset --hard ORIG_HEAD
git stash pop
```

<br />

**3. Configurar reflog para mantener entradas más tiempo:**
```elixir
# Mantener entradas de reflog por 180 días
git config gc.reflogExpire 180.days

# Mantener objetos inalcanzables por 60 días
git config gc.reflogExpireUnreachable 60.days
```

<br />

**4. Aprender a leer patrones de reflog:**
- `HEAD@{n}`: La enésima posición anterior de HEAD
- `branch@{n}`: La enésima posición anterior de un branch específico
- `@{-n}`: El enésimo branch del que hiciste checkout antes del actual
- `@{upstream}`: El branch upstream

<br />

##### **Cherry-Pick vs Merge vs Rebase**
¿Cuándo deberías usar cherry-pick en lugar de merge o rebase?

<br />

**Usar cherry-pick cuando:**
- Necesitás commits específicos, no branches enteros
- Backporting de fixes a branches de release
- Mover un commit al branch correcto
- Extraer commits de branches abandonados

<br />

**Usar merge cuando:**
- Combinar branches de features enteros
- Preservar historial completo
- Trabajar con branches compartidos

<br />

**Usar rebase cuando:**
- Limpiar historial local antes de pushear
- Actualizar feature branch con main
- Mantener historial lineal

<br />

##### **Solucionando Problemas Comunes**

**"fatal: ambiguous argument 'HEAD@{n}'"**
```elixir
# Escapar las llaves en algunos shells
git reset --hard 'HEAD@{1}'
# o
git reset --hard HEAD@\{1\}
```

<br />

**"warning: reflog of 'branch' references pruned commits"**
```elixir
# Los commits siguen ahí, solo inalcanzables
# Encontrarlos con
git fsck --unreachable | grep commit

# Recuperar commit inalcanzable específico
git show <sha-inalcanzable>
git branch recuperado <sha-inalcanzable>
```

<br />

**"error: could not apply abc123"**
```elixir
# Conflicto de cherry-pick
# Ver qué está en conflicto
git status

# Ver las diferencias
git diff

# Resolver y continuar, o abortar
git cherry-pick --abort
```

<br />

##### **Conclusión**
El reflog de Git es tu red de seguridad, y cjerry-pick es tu herramienta de precisión. Juntos, hacen que Git sea mucho menos aterrador. Recordá:

<br />

> * Git raramente borra algo verdaderamente de inmediato
> * El reflog es tu máquina del tiempo - ¡usala!
> * Cherry-pick cuando necesites precisión quirúrgica
> * Siempre creá branches de backup antes de operaciones riesgosas
> * Cuando tengas dudas, verificá el reflog

<br />

La próxima vez que pienses que perdiste trabajo en Git, no entres en pánico. Respirá, verificá el reflog, y recordá que tus commits probablemente están a solo unos comandos de distancia de ser recuperados. Git te cubre las espaldas, ¡solo necesitás saber cómo pedir ayuda!

<br />

Practicá estos comandos en un repositorio de prueba hasta que se vuelvan segunda naturaleza. La confianza de saber que podés recuperarte de casi cualquier error de Git es invaluable.

<br />

¡Hasta la próxima, que tus commits estén seguros y tu reflog siempre accesible!
