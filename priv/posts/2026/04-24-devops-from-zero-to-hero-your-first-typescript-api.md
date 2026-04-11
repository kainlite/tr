%{
  title: "DevOps from Zero to Hero: Your First TypeScript API with Express and Docker",
  author: "Gabriel Garrido",
  description: "We will build a simple REST API with TypeScript and Express, then containerize it with Docker using multi-stage builds and best practices...",
  tags: ~w(devops typescript docker beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article two of the DevOps from Zero to Hero series. In the first article we set up our
development environment and got familiar with the basic tools. Now it is time to build something
real: a REST API that we can deploy, test, and iterate on throughout the rest of the series.

<br />

We are going to build a simple task tracker API using TypeScript and Express. Nothing fancy, just
CRUD operations on an in-memory array. The goal is not to build a production-grade app right now,
but to have a working API that we can containerize, deploy, and improve in future articles.

<br />

After the API is working, we will write a Dockerfile using multi-stage builds, set up a
`.dockerignore`, run the container as a non-root user, add a health check endpoint, and wire
everything up with Docker Compose for local development with hot reload.

<br />

Let's get into it.

<br />

##### **Why TypeScript and Express?**
You might wonder why we are not using Python, Go, or something else. TypeScript with Express is one
of the most common stacks you will encounter in the wild. It has a massive ecosystem, the tooling
is mature, and the concepts translate directly to other languages and frameworks.

<br />

For DevOps, the language itself matters less than understanding how to build, test, package, and
deploy applications. We picked TypeScript because it gives us type safety without too much ceremony,
and Express because it is minimal enough that we can focus on the DevOps side of things.

<br />

##### **Project setup**
First, create a new directory and initialize the project:

<br />

```bash
mkdir task-api && cd task-api
npm init -y
```

<br />

Install the dependencies we need:

<br />

```bash
npm install express
npm install -D typescript @types/express @types/node ts-node nodemon
```

<br />

Now create the TypeScript configuration. This tells the compiler how to process our code:

<br />

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

<br />

Update your `package.json` scripts section:

<br />

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "nodemon --watch src --ext ts --exec ts-node src/index.ts"
  }
}
```

<br />

Create the source directory:

<br />

```bash
mkdir src
```

<br />

##### **Defining the task model**
Let's start with a simple type definition for our tasks. Create `src/types.ts`:

<br />

```typescript
// src/types.ts
export interface Task {
  id: number;
  title: string;
  description: string;
  completed: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateTaskRequest {
  title: string;
  description?: string;
}

export interface UpdateTaskRequest {
  title?: string;
  description?: string;
  completed?: boolean;
}
```

<br />

This gives us a clear contract for what a task looks like and what data we expect when creating or
updating one.

<br />

##### **Building the API**
Now let's build the actual API. Create `src/index.ts`:

<br />

```typescript
// src/index.ts
import express, { Request, Response } from "express";
import { Task, CreateTaskRequest, UpdateTaskRequest } from "./types";

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// In-memory storage
let tasks: Task[] = [];
let nextId = 1;

// Health check endpoint
app.get("/health", (_req: Request, res: Response) => {
  res.json({
    status: "healthy",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

// GET /tasks - List all tasks
app.get("/tasks", (_req: Request, res: Response) => {
  res.json({
    data: tasks,
    count: tasks.length,
  });
});

// GET /tasks/:id - Get a single task
app.get("/tasks/:id", (req: Request, res: Response) => {
  const task = tasks.find((t) => t.id === parseInt(req.params.id));
  if (!task) {
    res.status(404).json({ error: "Task not found" });
    return;
  }
  res.json({ data: task });
});

// POST /tasks - Create a new task
app.post("/tasks", (req: Request, res: Response) => {
  const body: CreateTaskRequest = req.body;

  if (!body.title || body.title.trim() === "") {
    res.status(400).json({ error: "Title is required" });
    return;
  }

  const now = new Date().toISOString();
  const task: Task = {
    id: nextId++,
    title: body.title.trim(),
    description: body.description?.trim() || "",
    completed: false,
    createdAt: now,
    updatedAt: now,
  };

  tasks.push(task);
  res.status(201).json({ data: task });
});

// PUT /tasks/:id - Update a task
app.put("/tasks/:id", (req: Request, res: Response) => {
  const taskIndex = tasks.findIndex((t) => t.id === parseInt(req.params.id));
  if (taskIndex === -1) {
    res.status(404).json({ error: "Task not found" });
    return;
  }

  const body: UpdateTaskRequest = req.body;
  const existing = tasks[taskIndex];

  const updated: Task = {
    ...existing,
    title: body.title?.trim() ?? existing.title,
    description: body.description?.trim() ?? existing.description,
    completed: body.completed ?? existing.completed,
    updatedAt: new Date().toISOString(),
  };

  tasks[taskIndex] = updated;
  res.json({ data: updated });
});

// DELETE /tasks/:id - Delete a task
app.delete("/tasks/:id", (req: Request, res: Response) => {
  const taskIndex = tasks.findIndex((t) => t.id === parseInt(req.params.id));
  if (taskIndex === -1) {
    res.status(404).json({ error: "Task not found" });
    return;
  }

  const deleted = tasks.splice(taskIndex, 1)[0];
  res.json({ data: deleted, message: "Task deleted" });
});

// Start the server
app.listen(PORT, () => {
  console.log(`Task API running on port ${PORT}`);
});

export default app;
```

<br />

##### **Testing the API locally**
Start the development server:

<br />

```bash
npm run dev
```

<br />

You should see `Task API running on port 3000`. Now let's test each endpoint with curl:

<br />

```bash
# Health check
curl http://localhost:3000/health | jq

# Create a task
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn Docker", "description": "Build and run containers"}' | jq

# Create another task
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Write Dockerfile", "description": "Multi-stage build"}' | jq

# List all tasks
curl http://localhost:3000/tasks | jq

# Get a single task
curl http://localhost:3000/tasks/1 | jq

# Update a task
curl -X PUT http://localhost:3000/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"completed": true}' | jq

# Delete a task
curl -X DELETE http://localhost:3000/tasks/2 | jq
```

<br />

You should see proper JSON responses for each request. The health check returns the server uptime,
the POST returns the created task with an auto-incremented ID, and so on.

<br />

##### **The Dockerfile**
Now we get to the fun part. We are going to containerize this API using Docker best practices.

<br />

First, let's talk about why multi-stage builds matter. A typical TypeScript project has development
dependencies (the compiler, type definitions, nodemon) that we do not need at runtime. With
multi-stage builds, we compile in one stage and copy only the output to a smaller final image. This
means smaller images, faster pulls, and a smaller attack surface.

<br />

Create the Dockerfile:

<br />

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first for better layer caching
COPY package*.json ./

# Install all dependencies (including devDependencies for building)
RUN npm ci

# Copy source code
COPY tsconfig.json ./
COPY src ./src

# Compile TypeScript
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS production

# Add a non-root user
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copy package files and install production-only dependencies
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy compiled output from builder stage
COPY --from=builder /app/dist ./dist

# Switch to non-root user
USER appuser

# Expose the port
EXPOSE 3000

# Set environment variable
ENV NODE_ENV=production

# Health check using the /health endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "dist/index.js"]
```

<br />

Let's break down what each part does:

<br />

> * **Multi-stage build** We use two stages. The first installs all dependencies and compiles TypeScript. The second only has production dependencies and the compiled JavaScript. This keeps the final image small.
> * **Alpine base** We use `node:20-alpine` instead of `node:20`. Alpine is a minimal Linux distribution that produces much smaller images.
> * **Layer caching** We copy `package*.json` before the source code. This means Docker can cache the `npm ci` layer and only reinstall dependencies when `package.json` changes.
> * **Non-root user** Running as root inside a container is a security risk. We create a dedicated user and switch to it before starting the app.
> * **Health check** Docker can monitor the container health by hitting our `/health` endpoint. Orchestrators like Kubernetes use this to know when to restart unhealthy containers.

<br />

##### **The .dockerignore file**
Just like `.gitignore` keeps files out of your repository, `.dockerignore` keeps files out of your
Docker build context. This makes builds faster and prevents sensitive files from leaking into images.

<br />

Create `.dockerignore`:

<br />

```bash
node_modules
dist
npm-debug.log
.git
.gitignore
.env
.env.*
*.md
.vscode
.idea
coverage
.nyc_output
```

<br />

The most important entry is `node_modules`. Without this, Docker would copy your entire local
`node_modules` directory into the build context, which is slow and unnecessary since we run
`npm ci` inside the container anyway.

<br />

##### **Building and running the container**
Build the image:

<br />

```bash
docker build -t task-api:latest .
```

<br />

You should see Docker executing both stages. The first time takes a bit longer because it downloads
the base image and installs dependencies. Subsequent builds are faster thanks to layer caching.

<br />

Check the image size:

<br />

```bash
docker images task-api
```

<br />

The Alpine-based multi-stage image should be around 130-150 MB. Compare that to a full `node:20`
image which starts at over 900 MB before you even add your code.

<br />

Run the container:

<br />

```bash
docker run -d --name task-api -p 3000:3000 task-api:latest
```

<br />

Test it:

<br />

```bash
# Health check
curl http://localhost:3000/health | jq

# Create a task
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Running in Docker!"}' | jq
```

<br />

Check the container health status:

<br />

```bash
docker inspect --format='{{.State.Health.Status}}' task-api
```

<br />

After about 30 seconds, it should show `healthy`.

<br />

Stop and remove the container when you are done:

<br />

```bash
docker stop task-api && docker rm task-api
```

<br />

##### **Docker Compose for local development**
Running `docker build` and `docker run` every time you change code gets old fast. Docker Compose
gives us a better workflow. We can define services, mount our source code as a volume, and get hot
reload inside the container.

<br />

Create `docker-compose.yml`:

<br />

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./src:/app/src
      - ./package.json:/app/package.json
    environment:
      - NODE_ENV=development
      - PORT=3000
    restart: unless-stopped
```

<br />

We need a separate Dockerfile for development since we want `ts-node` and `nodemon` available.
Create `Dockerfile.dev`:

<br />

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files and install all dependencies
COPY package*.json ./
RUN npm ci

# Copy TypeScript config
COPY tsconfig.json ./

# Copy source code (will be overridden by volume mount)
COPY src ./src

# Expose the port
EXPOSE 3000

# Run with nodemon for hot reload
CMD ["npx", "nodemon", "--watch", "src", "--ext", "ts", "--exec", "ts-node", "src/index.ts"]
```

<br />

Start the development environment:

<br />

```bash
docker compose up
```

<br />

Now edit `src/index.ts`, save the file, and watch nodemon restart automatically inside the
container. Your changes appear without rebuilding the image. This is the development workflow you
want: fast feedback loops while still running inside a container.

<br />

To run it in the background:

<br />

```bash
docker compose up -d
```

<br />

Check the logs:

<br />

```bash
docker compose logs -f api
```

<br />

Stop everything:

<br />

```bash
docker compose down
```

<br />

##### **Why containers matter for DevOps**
We just went from "code on my machine" to "code in a container." This might seem like extra work
for a simple API, but containers solve real problems that show up in every team:

<br />

> * **Reproducibility** The container runs the same way on your laptop, in CI, and in production. No more "it works on my machine" conversations.
> * **Consistency** Everyone on the team uses the same Node.js version, the same OS, the same dependencies. The Dockerfile is the single source of truth.
> * **Isolation** Your app runs in its own filesystem and network namespace. It does not conflict with other services on the same machine.
> * **Portability** The image runs anywhere Docker runs: local machines, cloud VMs, Kubernetes clusters. You build once and deploy anywhere.
> * **Immutability** Once built, the image does not change. You do not SSH into production and tweak files. You build a new image and deploy it.

<br />

These properties are the foundation of modern DevOps. Every tool and practice we cover in this
series builds on top of containers. CI/CD pipelines build container images. Kubernetes orchestrates
them. GitOps tracks which image version runs where. Without containers, none of that works as
smoothly.

<br />

##### **Project structure recap**
At this point, your project should look like this:

<br />

```bash
task-api/
├── src/
│   ├── index.ts
│   └── types.ts
├── .dockerignore
├── docker-compose.yml
├── Dockerfile
├── Dockerfile.dev
├── package.json
├── package-lock.json
└── tsconfig.json
```

<br />

##### **Closing notes**
In this article we built a complete REST API with TypeScript and Express, then containerized it
using Docker best practices. We covered multi-stage builds, non-root users, health checks,
`.dockerignore`, and Docker Compose for local development.

<br />

The API itself is intentionally simple. It stores tasks in memory, which means all data disappears
when the container restarts. That is fine for now. In a future article we will add a real database
and learn how to manage data persistence with containers.

<br />

In the next article, we will set up a CI/CD pipeline that automatically builds our Docker image,
runs tests, and pushes the image to a container registry. That is where the DevOps workflow really
starts to come together.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps de Cero a Heroe: Tu Primera API en TypeScript con Express y Docker",
  author: "Gabriel Garrido",
  description: "Vamos a construir una API REST simple con TypeScript y Express, y despues la vamos a containerizar con Docker usando multi-stage builds y buenas practicas...",
  tags: ~w(devops typescript docker beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al segundo articulo de la serie DevOps de Cero a Heroe. En el primer articulo
configuramos nuestro entorno de desarrollo y nos familiarizamos con las herramientas basicas. Ahora
es momento de construir algo real: una API REST que vamos a poder deployar, testear e iterar a lo
largo del resto de la serie.

<br />

Vamos a armar un task tracker simple usando TypeScript y Express. Nada sofisticado, solo operaciones
CRUD sobre un array en memoria. El objetivo no es hacer una app production-ready ahora, sino tener
una API funcionando que podamos containerizar, deployar y mejorar en los proximos articulos.

<br />

Despues de que la API este andando, vamos a escribir un Dockerfile usando multi-stage builds,
configurar un `.dockerignore`, correr el container con un usuario no-root, agregar un endpoint de
health check, y armar todo con Docker Compose para desarrollo local con hot reload.

<br />

Vamos a ello.

<br />

##### **Por que TypeScript y Express?**
Puede que te preguntes por que no usamos Python, Go, o algo distinto. TypeScript con Express es uno
de los stacks mas comunes que te vas a encontrar en la vida real. Tiene un ecosistema enorme, el
tooling es maduro, y los conceptos se traducen directamente a otros lenguajes y frameworks.

<br />

Para DevOps, el lenguaje en si importa menos que entender como buildear, testear, empaquetar y
deployar aplicaciones. Elegimos TypeScript porque nos da type safety sin demasiada ceremonia, y
Express porque es lo suficientemente minimalista como para que podamos enfocarnos en el lado DevOps
de las cosas.

<br />

##### **Configuracion del proyecto**
Primero, crea un directorio nuevo e inicializa el proyecto:

<br />

```bash
mkdir task-api && cd task-api
npm init -y
```

<br />

Instala las dependencias que necesitamos:

<br />

```bash
npm install express
npm install -D typescript @types/express @types/node ts-node nodemon
```

<br />

Ahora crea la configuracion de TypeScript. Esto le dice al compilador como procesar nuestro codigo:

<br />

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

<br />

Actualiza la seccion de scripts de tu `package.json`:

<br />

```json
{
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "nodemon --watch src --ext ts --exec ts-node src/index.ts"
  }
}
```

<br />

Crea el directorio de codigo fuente:

<br />

```bash
mkdir src
```

<br />

##### **Definiendo el modelo de tareas**
Arranquemos con una definicion de tipos simple para nuestras tareas. Crea `src/types.ts`:

<br />

```typescript
// src/types.ts
export interface Task {
  id: number;
  title: string;
  description: string;
  completed: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateTaskRequest {
  title: string;
  description?: string;
}

export interface UpdateTaskRequest {
  title?: string;
  description?: string;
  completed?: boolean;
}
```

<br />

Esto nos da un contrato claro de como se ve una tarea y que datos esperamos al crear o actualizar
una.

<br />

##### **Construyendo la API**
Ahora armemos la API propiamente dicha. Crea `src/index.ts`:

<br />

```typescript
// src/index.ts
import express, { Request, Response } from "express";
import { Task, CreateTaskRequest, UpdateTaskRequest } from "./types";

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// In-memory storage
let tasks: Task[] = [];
let nextId = 1;

// Health check endpoint
app.get("/health", (_req: Request, res: Response) => {
  res.json({
    status: "healthy",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

// GET /tasks - List all tasks
app.get("/tasks", (_req: Request, res: Response) => {
  res.json({
    data: tasks,
    count: tasks.length,
  });
});

// GET /tasks/:id - Get a single task
app.get("/tasks/:id", (req: Request, res: Response) => {
  const task = tasks.find((t) => t.id === parseInt(req.params.id));
  if (!task) {
    res.status(404).json({ error: "Task not found" });
    return;
  }
  res.json({ data: task });
});

// POST /tasks - Create a new task
app.post("/tasks", (req: Request, res: Response) => {
  const body: CreateTaskRequest = req.body;

  if (!body.title || body.title.trim() === "") {
    res.status(400).json({ error: "Title is required" });
    return;
  }

  const now = new Date().toISOString();
  const task: Task = {
    id: nextId++,
    title: body.title.trim(),
    description: body.description?.trim() || "",
    completed: false,
    createdAt: now,
    updatedAt: now,
  };

  tasks.push(task);
  res.status(201).json({ data: task });
});

// PUT /tasks/:id - Update a task
app.put("/tasks/:id", (req: Request, res: Response) => {
  const taskIndex = tasks.findIndex((t) => t.id === parseInt(req.params.id));
  if (taskIndex === -1) {
    res.status(404).json({ error: "Task not found" });
    return;
  }

  const body: UpdateTaskRequest = req.body;
  const existing = tasks[taskIndex];

  const updated: Task = {
    ...existing,
    title: body.title?.trim() ?? existing.title,
    description: body.description?.trim() ?? existing.description,
    completed: body.completed ?? existing.completed,
    updatedAt: new Date().toISOString(),
  };

  tasks[taskIndex] = updated;
  res.json({ data: updated });
});

// DELETE /tasks/:id - Delete a task
app.delete("/tasks/:id", (req: Request, res: Response) => {
  const taskIndex = tasks.findIndex((t) => t.id === parseInt(req.params.id));
  if (taskIndex === -1) {
    res.status(404).json({ error: "Task not found" });
    return;
  }

  const deleted = tasks.splice(taskIndex, 1)[0];
  res.json({ data: deleted, message: "Task deleted" });
});

// Start the server
app.listen(PORT, () => {
  console.log(`Task API running on port ${PORT}`);
});

export default app;
```

<br />

##### **Probando la API localmente**
Inicia el servidor de desarrollo:

<br />

```bash
npm run dev
```

<br />

Deberias ver `Task API running on port 3000`. Ahora probemos cada endpoint con curl:

<br />

```bash
# Health check
curl http://localhost:3000/health | jq

# Crear una tarea
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Learn Docker", "description": "Build and run containers"}' | jq

# Crear otra tarea
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Write Dockerfile", "description": "Multi-stage build"}' | jq

# Listar todas las tareas
curl http://localhost:3000/tasks | jq

# Obtener una tarea especifica
curl http://localhost:3000/tasks/1 | jq

# Actualizar una tarea
curl -X PUT http://localhost:3000/tasks/1 \
  -H "Content-Type: application/json" \
  -d '{"completed": true}' | jq

# Eliminar una tarea
curl -X DELETE http://localhost:3000/tasks/2 | jq
```

<br />

Deberias ver respuestas JSON correctas para cada request. El health check devuelve el uptime del
servidor, el POST devuelve la tarea creada con un ID auto-incrementado, y asi sucesivamente.

<br />

##### **El Dockerfile**
Ahora viene la parte divertida. Vamos a containerizar esta API usando buenas practicas de Docker.

<br />

Primero, hablemos de por que importan los multi-stage builds. Un proyecto TypeScript tipico tiene
dependencias de desarrollo (el compilador, definiciones de tipos, nodemon) que no necesitamos en
runtime. Con multi-stage builds, compilamos en una etapa y copiamos solo el output a una imagen
final mas chica. Esto significa imagenes mas livianas, pulls mas rapidos, y una superficie de
ataque menor.

<br />

Crea el Dockerfile:

<br />

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder

WORKDIR /app

# Copiamos los archivos de paquete primero para mejor cache de capas
COPY package*.json ./

# Instalamos todas las dependencias (incluyendo devDependencies para el build)
RUN npm ci

# Copiamos el codigo fuente
COPY tsconfig.json ./
COPY src ./src

# Compilamos TypeScript
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS production

# Agregamos un usuario no-root
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copiamos archivos de paquete e instalamos solo dependencias de produccion
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copiamos el output compilado desde la etapa builder
COPY --from=builder /app/dist ./dist

# Cambiamos al usuario no-root
USER appuser

# Exponemos el puerto
EXPOSE 3000

# Variable de entorno
ENV NODE_ENV=production

# Health check usando el endpoint /health
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Iniciamos la aplicacion
CMD ["node", "dist/index.js"]
```

<br />

Repasemos que hace cada parte:

<br />

> * **Multi-stage build** Usamos dos etapas. La primera instala todas las dependencias y compila TypeScript. La segunda solo tiene dependencias de produccion y el JavaScript compilado. Esto mantiene la imagen final liviana.
> * **Base Alpine** Usamos `node:20-alpine` en vez de `node:20`. Alpine es una distribucion Linux minima que produce imagenes mucho mas chicas.
> * **Cache de capas** Copiamos `package*.json` antes del codigo fuente. Esto significa que Docker puede cachear la capa de `npm ci` y solo reinstalar dependencias cuando cambie `package.json`.
> * **Usuario no-root** Correr como root dentro de un container es un riesgo de seguridad. Creamos un usuario dedicado y cambiamos a el antes de iniciar la app.
> * **Health check** Docker puede monitorear la salud del container llamando a nuestro endpoint `/health`. Orquestadores como Kubernetes usan esto para saber cuando reiniciar containers no saludables.

<br />

##### **El archivo .dockerignore**
Asi como `.gitignore` mantiene archivos fuera de tu repositorio, `.dockerignore` mantiene archivos
fuera de tu contexto de build de Docker. Esto hace que los builds sean mas rapidos y previene que
archivos sensibles se filtren en las imagenes.

<br />

Crea `.dockerignore`:

<br />

```bash
node_modules
dist
npm-debug.log
.git
.gitignore
.env
.env.*
*.md
.vscode
.idea
coverage
.nyc_output
```

<br />

La entrada mas importante es `node_modules`. Sin esto, Docker copiaria todo tu directorio
`node_modules` local al contexto de build, lo cual es lento e innecesario ya que corremos `npm ci`
dentro del container de todas formas.

<br />

##### **Construyendo y corriendo el container**
Construi la imagen:

<br />

```bash
docker build -t task-api:latest .
```

<br />

Deberias ver a Docker ejecutando ambas etapas. La primera vez tarda un poco mas porque descarga la
imagen base e instala dependencias. Los builds siguientes son mas rapidos gracias al cache de capas.

<br />

Verifica el tamanio de la imagen:

<br />

```bash
docker images task-api
```

<br />

La imagen multi-stage basada en Alpine deberia estar alrededor de 130-150 MB. Compara eso con una
imagen `node:20` completa que arranca en mas de 900 MB antes de que le agregues tu codigo.

<br />

Corre el container:

<br />

```bash
docker run -d --name task-api -p 3000:3000 task-api:latest
```

<br />

Probalo:

<br />

```bash
# Health check
curl http://localhost:3000/health | jq

# Crear una tarea
curl -X POST http://localhost:3000/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Corriendo en Docker!"}' | jq
```

<br />

Verifica el estado de salud del container:

<br />

```bash
docker inspect --format='{{.State.Health.Status}}' task-api
```

<br />

Despues de unos 30 segundos, deberia mostrar `healthy`.

<br />

Para y elimina el container cuando termines:

<br />

```bash
docker stop task-api && docker rm task-api
```

<br />

##### **Docker Compose para desarrollo local**
Correr `docker build` y `docker run` cada vez que cambias codigo se vuelve tedioso rapido. Docker
Compose nos da un mejor flujo de trabajo. Podemos definir servicios, montar nuestro codigo fuente
como volumen, y tener hot reload dentro del container.

<br />

Crea `docker-compose.yml`:

<br />

```yaml
services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./src:/app/src
      - ./package.json:/app/package.json
    environment:
      - NODE_ENV=development
      - PORT=3000
    restart: unless-stopped
```

<br />

Necesitamos un Dockerfile separado para desarrollo ya que queremos tener `ts-node` y `nodemon`
disponibles. Crea `Dockerfile.dev`:

<br />

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copiamos archivos de paquete e instalamos todas las dependencias
COPY package*.json ./
RUN npm ci

# Copiamos la configuracion de TypeScript
COPY tsconfig.json ./

# Copiamos el codigo fuente (sera sobreescrito por el volume mount)
COPY src ./src

# Exponemos el puerto
EXPOSE 3000

# Corremos con nodemon para hot reload
CMD ["npx", "nodemon", "--watch", "src", "--ext", "ts", "--exec", "ts-node", "src/index.ts"]
```

<br />

Inicia el entorno de desarrollo:

<br />

```bash
docker compose up
```

<br />

Ahora edita `src/index.ts`, guarda el archivo, y mira como nodemon reinicia automaticamente dentro
del container. Tus cambios aparecen sin reconstruir la imagen. Este es el flujo de desarrollo que
queres: ciclos de feedback rapidos mientras seguis corriendo dentro de un container.

<br />

Para correrlo en background:

<br />

```bash
docker compose up -d
```

<br />

Ver los logs:

<br />

```bash
docker compose logs -f api
```

<br />

Parar todo:

<br />

```bash
docker compose down
```

<br />

##### **Por que importan los containers para DevOps**
Acabamos de pasar de "codigo en mi maquina" a "codigo en un container." Puede parecer trabajo extra
para una API simple, pero los containers resuelven problemas reales que aparecen en todos los
equipos:

<br />

> * **Reproducibilidad** El container corre igual en tu laptop, en CI, y en produccion. No mas conversaciones de "en mi maquina funciona."
> * **Consistencia** Todos en el equipo usan la misma version de Node.js, el mismo SO, las mismas dependencias. El Dockerfile es la unica fuente de verdad.
> * **Aislamiento** Tu app corre en su propio filesystem y namespace de red. No genera conflictos con otros servicios en la misma maquina.
> * **Portabilidad** La imagen corre donde sea que Docker corra: maquinas locales, VMs en la nube, clusters de Kubernetes. Buildeas una vez y deployeas donde quieras.
> * **Inmutabilidad** Una vez construida, la imagen no cambia. No te conectas por SSH a produccion para tocar archivos. Buildeas una imagen nueva y la deployeas.

<br />

Estas propiedades son la base del DevOps moderno. Cada herramienta y practica que cubrimos en esta
serie se construye sobre containers. Los pipelines de CI/CD buildean imagenes de containers.
Kubernetes los orquesta. GitOps trackea que version de imagen corre donde. Sin containers, nada de
eso funciona tan fluidamente.

<br />

##### **Resumen de la estructura del proyecto**
A este punto, tu proyecto deberia verse asi:

<br />

```bash
task-api/
├── src/
│   ├── index.ts
│   └── types.ts
├── .dockerignore
├── docker-compose.yml
├── Dockerfile
├── Dockerfile.dev
├── package.json
├── package-lock.json
└── tsconfig.json
```

<br />

##### **Notas finales**
En este articulo construimos una API REST completa con TypeScript y Express, y despues la
containerizamos usando buenas practicas de Docker. Cubrimos multi-stage builds, usuarios no-root,
health checks, `.dockerignore`, y Docker Compose para desarrollo local.

<br />

La API en si es intencionalmente simple. Guarda tareas en memoria, lo que significa que todos los
datos desaparecen cuando el container se reinicia. Eso esta bien por ahora. En un articulo futuro
vamos a agregar una base de datos real y aprender a manejar persistencia de datos con containers.

<br />

En el proximo articulo, vamos a configurar un pipeline de CI/CD que automaticamente buildee nuestra
imagen Docker, corra tests, y pushee la imagen a un container registry. Ahi es donde el flujo de
trabajo DevOps realmente empieza a tomar forma.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje para que lo pueda corregir.

Tambien podes ver el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
