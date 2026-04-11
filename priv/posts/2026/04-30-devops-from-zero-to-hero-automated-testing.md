%{
  title: "DevOps from Zero to Hero: Automated Testing",
  author: "Gabriel Garrido",
  description: "We will explore the testing pyramid, write unit and integration tests with Vitest and Supertest, and discuss why coverage metrics can be misleading...",
  tags: ~w(devops typescript testing beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
Welcome to article four of the DevOps from Zero to Hero series. In the previous articles we covered
the fundamentals of Linux, networking, and version control with Git. Now it is time to talk about
something that separates hobby projects from production-ready software: automated testing.

<br />

If you have ever pushed a change to production and immediately regretted it, you already understand
why testing matters. Automated tests give you confidence that your code works as expected before it
reaches users. In a DevOps context, tests are the gate between "code written" and "code deployed."
Without them, your CI/CD pipeline is just a fast way to ship bugs.

<br />

In this article we will cover the testing pyramid, write real unit and integration tests in TypeScript
using Vitest and Supertest, talk about what coverage actually means (and why chasing 100% is a trap),
and lay the groundwork for running tests in CI, which we will cover in depth in article five.

<br />

Let's get into it.

<br />

##### **Why testing matters for DevOps**
Testing is not just a developer concern. In a DevOps workflow, tests are the foundation of everything
else you build. Here is why:

<br />

> * **Confidence to deploy**: If your tests pass, you can deploy without fear. If they do not, you know something is broken before users do.
> * **Fast feedback**: A good test suite tells you within minutes whether a change is safe. Compare that to waiting for manual QA or finding out from a user report.
> * **Catch regressions**: Code that worked yesterday can break today because of a seemingly unrelated change. Tests catch these regressions automatically.
> * **Enable automation**: CI/CD pipelines depend on tests. Without automated tests, your pipeline is just automated deployment of untested code.
> * **Documentation**: Well-written tests describe what your code should do. They serve as living documentation that stays in sync with the actual behavior.

<br />

Think of it this way: every test you write is a tiny contract that says "this behavior must be
preserved." When someone changes the code six months from now, those contracts catch anything that
breaks. That is incredibly valuable in a team environment where multiple people touch the same
codebase.

<br />

##### **The testing pyramid**
The testing pyramid is a model that helps you decide how many tests of each type to write. It looks
like this:

<br />

```
        /  E2E  \          Few, slow, expensive
       /----------\
      / Integration \      Some, moderate speed
     /----------------\
    /    Unit Tests     \  Many, fast, cheap
   /____________________\
```

<br />

The shape matters. Here is why:

<br />

> * **Unit tests** (base of the pyramid): These test individual functions or modules in isolation. They are fast, cheap to write, and cheap to run. You should have the most of these.
> * **Integration tests** (middle): These test how multiple pieces work together, like an API endpoint hitting a database. They are slower and more complex, but they catch issues that unit tests miss.
> * **End-to-end tests** (top): These test the entire application from the user's perspective, often through a browser. They are the slowest, most fragile, and most expensive to maintain. You should have the fewest of these.

<br />

The pyramid shape exists because of a tradeoff between speed and confidence. Unit tests run in
milliseconds but only test small pieces. E2E tests take seconds or minutes but test the full flow.
If you invert the pyramid (lots of E2E, few unit tests), your test suite becomes slow, flaky, and
painful to maintain.

<br />

A healthy ratio might look something like 70% unit, 20% integration, 10% E2E. These numbers are
not rules, they are guidelines. The key insight is: push testing down to the lowest level that gives
you confidence. If you can catch a bug with a unit test, do not write an E2E test for it.

<br />

##### **Setting up the project**
Let's build a small TypeScript project with tests. We will use Vitest as our test runner because it
is fast, modern, and works great with TypeScript out of the box.

<br />

First, initialize the project:

<br />

```bash
mkdir testing-demo && cd testing-demo
npm init -y
npm install -D typescript vitest @types/node
npm install express
npm install -D @types/express supertest @types/supertest
```

<br />

Create a `tsconfig.json`:

<br />

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

<br />

Add the test script to `package.json`:

<br />

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

<br />

##### **Unit testing with Vitest**
Let's start with the base of the pyramid. Unit tests verify that individual functions do what they
are supposed to do. They should be fast, isolated, and deterministic.

<br />

Here is a simple utility module at `src/utils.ts`:

<br />

```typescript
// src/utils.ts

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

export function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text;
  }
  const truncated = text.slice(0, maxLength);
  const lastSpace = truncated.lastIndexOf(" ");
  if (lastSpace > 0) {
    return truncated.slice(0, lastSpace) + "...";
  }
  return truncated + "...";
}

export function parseQueryParams(query: string): Record<string, string> {
  if (!query || query.trim() === "") {
    return {};
  }
  const cleaned = query.startsWith("?") ? query.slice(1) : query;
  return cleaned.split("&").reduce(
    (params, pair) => {
      const [key, value] = pair.split("=");
      if (key) {
        params[decodeURIComponent(key)] = decodeURIComponent(value ?? "");
      }
      return params;
    },
    {} as Record<string, string>,
  );
}
```

<br />

Now let's write the tests at `src/utils.test.ts`:

<br />

```typescript
// src/utils.test.ts
import { describe, it, expect } from "vitest";
import { slugify, truncate, parseQueryParams } from "./utils";

describe("slugify", () => {
  it("converts a simple string to a slug", () => {
    expect(slugify("Hello World")).toBe("hello-world");
  });

  it("handles special characters", () => {
    expect(slugify("Hello, World! How's it going?")).toBe(
      "hello-world-hows-it-going",
    );
  });

  it("collapses multiple spaces and dashes", () => {
    expect(slugify("too   many   spaces")).toBe("too-many-spaces");
    expect(slugify("too---many---dashes")).toBe("too-many-dashes");
  });

  it("trims leading and trailing dashes", () => {
    expect(slugify("  -hello-  ")).toBe("hello");
  });

  it("handles empty string", () => {
    expect(slugify("")).toBe("");
  });
});

describe("truncate", () => {
  it("returns the full string if it is shorter than maxLength", () => {
    expect(truncate("short", 10)).toBe("short");
  });

  it("returns the full string if it equals maxLength", () => {
    expect(truncate("exact", 5)).toBe("exact");
  });

  it("truncates at the last space before maxLength", () => {
    expect(truncate("this is a longer sentence", 15)).toBe("this is a...");
  });

  it("truncates without space if no space is found", () => {
    expect(truncate("superlongwordwithoutspaces", 10)).toBe(
      "superlongw...",
    );
  });
});

describe("parseQueryParams", () => {
  it("parses a simple query string", () => {
    expect(parseQueryParams("name=alice&age=30")).toEqual({
      name: "alice",
      age: "30",
    });
  });

  it("handles a leading question mark", () => {
    expect(parseQueryParams("?foo=bar")).toEqual({ foo: "bar" });
  });

  it("handles URL-encoded values", () => {
    expect(parseQueryParams("msg=hello%20world")).toEqual({
      msg: "hello world",
    });
  });

  it("returns an empty object for empty input", () => {
    expect(parseQueryParams("")).toEqual({});
  });

  it("handles keys without values", () => {
    expect(parseQueryParams("flag=")).toEqual({ flag: "" });
  });
});
```

<br />

Let's break down the test structure:

<br />

> * **`describe`** groups related tests. Think of it as a section header for a set of behaviors.
> * **`it`** defines an individual test case. The string should read like a sentence: "it converts a simple string to a slug."
> * **`expect`** is the assertion. It takes a value and chains a matcher like `toBe`, `toEqual`, `toContain`, or `toThrow`.

<br />

Run the tests:

<br />

```bash
npx vitest run

# Output:
# ✓ src/utils.test.ts (10 tests) 5ms
#   ✓ slugify (5 tests)
#   ✓ truncate (4 tests)
#   ✓ parseQueryParams (5 tests)
# Test Files  1 passed (1)
# Tests       14 passed (14)
```

<br />

##### **Mocking dependencies**
Real-world code has dependencies: databases, APIs, file systems. In unit tests, you want to isolate
the function under test by replacing those dependencies with controlled substitutes. This is called
mocking.

<br />

Here is a module that depends on an external API at `src/weather.ts`:

<br />

```typescript
// src/weather.ts

export interface WeatherData {
  city: string;
  temperature: number;
  description: string;
}

export async function fetchWeather(city: string): Promise<WeatherData> {
  const response = await fetch(
    `https://api.weather.example.com/v1/current?city=${encodeURIComponent(city)}`,
  );
  if (!response.ok) {
    throw new Error(`Weather API returned ${response.status}`);
  }
  const data = await response.json();
  return {
    city: data.location.name,
    temperature: data.current.temp_c,
    description: data.current.condition.text,
  };
}

export function formatWeatherReport(weather: WeatherData): string {
  return `${weather.city}: ${weather.temperature}C, ${weather.description}`;
}
```

<br />

And the tests at `src/weather.test.ts`:

<br />

```typescript
// src/weather.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { fetchWeather, formatWeatherReport } from "./weather";

// Mock the global fetch function
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
});

describe("fetchWeather", () => {
  it("returns parsed weather data on success", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        location: { name: "London" },
        current: { temp_c: 15, condition: { text: "Partly cloudy" } },
      }),
    });

    const result = await fetchWeather("London");

    expect(result).toEqual({
      city: "London",
      temperature: 15,
      description: "Partly cloudy",
    });
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.weather.example.com/v1/current?city=London",
    );
  });

  it("throws on non-ok response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    await expect(fetchWeather("Nowhere")).rejects.toThrow(
      "Weather API returned 404",
    );
  });
});

describe("formatWeatherReport", () => {
  it("formats the weather data as a readable string", () => {
    const weather = {
      city: "Berlin",
      temperature: 22,
      description: "Sunny",
    };
    expect(formatWeatherReport(weather)).toBe("Berlin: 22C, Sunny");
  });
});
```

<br />

Key mocking concepts:

<br />

> * **`vi.fn()`** creates a mock function that records how it was called.
> * **`vi.stubGlobal()`** replaces a global like `fetch` with your mock.
> * **`mockResolvedValueOnce()`** tells the mock what to return the next time it is called.
> * **`mockReset()`** clears the mock state between tests so they do not leak into each other.

<br />

The important thing to understand about mocking is this: you are not testing `fetch`. You are testing
that your code correctly handles the response from `fetch`. The mock lets you simulate different
scenarios (success, error, timeout) without making real network calls.

<br />

##### **Integration testing with Supertest**
Integration tests verify that multiple pieces of your application work together. For web
applications, the most common integration test is hitting an API endpoint and verifying the response.

<br />

Here is a simple Express app at `src/app.ts`:

<br />

```typescript
// src/app.ts
import express from "express";
import { slugify, truncate } from "./utils";

export const app = express();

app.use(express.json());

interface Article {
  id: number;
  title: string;
  slug: string;
  content: string;
  summary?: string;
}

const articles: Article[] = [];
let nextId = 1;

app.get("/api/articles", (_req, res) => {
  res.json(articles);
});

app.get("/api/articles/:slug", (req, res) => {
  const article = articles.find((a) => a.slug === req.params.slug);
  if (!article) {
    res.status(404).json({ error: "Article not found" });
    return;
  }
  res.json(article);
});

app.post("/api/articles", (req, res) => {
  const { title, content } = req.body;
  if (!title || !content) {
    res.status(400).json({ error: "Title and content are required" });
    return;
  }
  const article: Article = {
    id: nextId++,
    title,
    slug: slugify(title),
    content,
    summary: truncate(content, 100),
  };
  articles.push(article);
  res.status(201).json(article);
});

app.delete("/api/articles/:slug", (req, res) => {
  const index = articles.findIndex((a) => a.slug === req.params.slug);
  if (index === -1) {
    res.status(404).json({ error: "Article not found" });
    return;
  }
  articles.splice(index, 1);
  res.status(204).send();
});
```

<br />

Now the integration tests at `src/app.test.ts`:

<br />

```typescript
// src/app.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { app } from "./app";

describe("Articles API", () => {
  // Note: In a real app, you would reset the database between tests.
  // Here we rely on the in-memory array.

  describe("POST /api/articles", () => {
    it("creates a new article", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({
          title: "My First Post",
          content:
            "This is the content of my first blog post. It has enough words to test truncation properly.",
        })
        .expect(201);

      expect(response.body).toMatchObject({
        title: "My First Post",
        slug: "my-first-post",
        content:
          "This is the content of my first blog post. It has enough words to test truncation properly.",
      });
      expect(response.body.id).toBeDefined();
      expect(response.body.summary).toBeDefined();
    });

    it("returns 400 when title is missing", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({ content: "some content" })
        .expect(400);

      expect(response.body.error).toBe("Title and content are required");
    });

    it("returns 400 when content is missing", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({ title: "A Title" })
        .expect(400);

      expect(response.body.error).toBe("Title and content are required");
    });
  });

  describe("GET /api/articles", () => {
    it("returns the list of articles", async () => {
      const response = await request(app).get("/api/articles").expect(200);

      expect(Array.isArray(response.body)).toBe(true);
      expect(response.body.length).toBeGreaterThan(0);
    });
  });

  describe("GET /api/articles/:slug", () => {
    it("returns an article by slug", async () => {
      const response = await request(app)
        .get("/api/articles/my-first-post")
        .expect(200);

      expect(response.body.slug).toBe("my-first-post");
      expect(response.body.title).toBe("My First Post");
    });

    it("returns 404 for a non-existent slug", async () => {
      const response = await request(app)
        .get("/api/articles/does-not-exist")
        .expect(404);

      expect(response.body.error).toBe("Article not found");
    });
  });

  describe("DELETE /api/articles/:slug", () => {
    it("deletes an article by slug", async () => {
      // First, create an article to delete
      await request(app)
        .post("/api/articles")
        .send({ title: "To Be Deleted", content: "This will be removed" });

      await request(app)
        .delete("/api/articles/to-be-deleted")
        .expect(204);

      // Verify it is gone
      await request(app)
        .get("/api/articles/to-be-deleted")
        .expect(404);
    });

    it("returns 404 when deleting a non-existent article", async () => {
      await request(app)
        .delete("/api/articles/ghost-article")
        .expect(404);
    });
  });
});
```

<br />

Notice how integration tests differ from unit tests:

<br />

> * **They test the full request/response cycle**, not just a single function.
> * **They exercise multiple layers** (routing, validation, business logic) together.
> * **They are slower** because they spin up the HTTP layer, but they catch bugs that unit tests cannot, like incorrect route definitions or missing middleware.

<br />

Supertest is excellent because it does not require you to start the server on a port. It hooks
directly into Express, so tests are fast and do not conflict with each other.

<br />

##### **Testing against real databases with Testcontainers**
For applications that use a database, you need to decide: do you mock the database or use a real one?
Mocking is faster but can hide bugs related to SQL syntax, constraints, or query behavior.
Testcontainers gives you the best of both worlds by spinning up a real database in Docker for your
tests.

<br />

Here is what using Testcontainers looks like conceptually:

<br />

```typescript
// src/db.integration.test.ts (conceptual example)
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PostgreSqlContainer } from "@testcontainers/postgresql";
import { Client } from "pg";

describe("Database integration", () => {
  let container: any;
  let client: Client;

  beforeAll(async () => {
    // Start a real PostgreSQL container
    container = await new PostgreSqlContainer("postgres:16")
      .withDatabase("testdb")
      .start();

    client = new Client({
      connectionString: container.getConnectionUri(),
    });
    await client.connect();

    // Run migrations
    await client.query(`
      CREATE TABLE articles (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        slug TEXT UNIQUE NOT NULL,
        content TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
  }, 60000); // Containers can take a moment to start

  afterAll(async () => {
    await client.end();
    await container.stop();
  });

  it("inserts and retrieves an article", async () => {
    await client.query(
      "INSERT INTO articles (title, slug, content) VALUES ($1, $2, $3)",
      ["Test Article", "test-article", "Some content"],
    );

    const result = await client.query(
      "SELECT * FROM articles WHERE slug = $1",
      ["test-article"],
    );

    expect(result.rows).toHaveLength(1);
    expect(result.rows[0].title).toBe("Test Article");
  });
});
```

<br />

Testcontainers is especially useful because:

<br />

> * **Tests run against the same database engine** you use in production, catching driver-specific bugs.
> * **Each test suite gets a fresh container**, so tests do not interfere with each other.
> * **It works in CI** as long as Docker is available (which it usually is in GitHub Actions).
> * **No shared test database** that accumulates stale data or causes flaky tests from parallel runs.

<br />

The tradeoff is speed: starting a container takes a few seconds. For this reason, Testcontainers
tests belong in the integration tier, not the unit tier.

<br />

##### **Test naming conventions and organization**
How you name and organize tests matters more than you might think. In six months, when a test fails
in CI, the test name is the first thing you will see. A good name tells you exactly what broke
without reading the code.

<br />

Here are some conventions that work well:

<br />

**File organization:**

<br />

```
src/
  utils.ts
  utils.test.ts        # Co-located with the source file
  app.ts
  app.test.ts
  weather.ts
  weather.test.ts
```

<br />

Co-locating tests with source files makes it obvious which file a test covers. Some teams prefer a
separate `__tests__` directory, but co-location has the advantage that when you rename or move a file,
the test moves with it.

<br />

**Naming patterns:**

<br />

```typescript
// Good: Describes the behavior clearly
describe("slugify", () => {
  it("converts spaces to dashes", () => {});
  it("removes special characters", () => {});
  it("handles empty string", () => {});
});

// Bad: Vague or implementation-focused
describe("slugify", () => {
  it("works", () => {});
  it("test 1", () => {});
  it("uses regex", () => {}); // who cares about the implementation?
});
```

<br />

The test name should answer: "What behavior does this test verify?" When it fails, the output should
read like a bug report: `slugify > removes special characters: FAILED`.

<br />

##### **What coverage actually means**
Code coverage measures what percentage of your code is executed when your tests run. You can generate
a coverage report with Vitest:

<br />

```bash
npx vitest run --coverage
```

<br />

This gives you metrics like:

<br />

> * **Line coverage**: What percentage of lines were executed?
> * **Branch coverage**: What percentage of if/else paths were taken?
> * **Function coverage**: What percentage of functions were called?
> * **Statement coverage**: What percentage of statements were executed?

<br />

A coverage report might look like this:

<br />

```bash
# ------------------|---------|----------|---------|---------|
# File              | % Stmts | % Branch | % Funcs | % Lines |
# ------------------|---------|----------|---------|---------|
# src/utils.ts      |   100   |   100    |   100   |   100   |
# src/weather.ts    |    85   |    75    |   100   |    85   |
# src/app.ts        |    92   |    80    |   100   |    92   |
# ------------------|---------|----------|---------|---------|
```

<br />

**Why 100% coverage is a trap:**

<br />

Coverage tells you what code was executed, not what code was tested correctly. Consider this:

<br />

```typescript
// This test has 100% coverage of the add function
function add(a: number, b: number): number {
  return a + b;
}

it("covers the add function", () => {
  add(1, 2); // Look, we called it! 100% coverage!
  // But we never checked the result...
});
```

<br />

That test executes every line of `add` but proves nothing. The function could return `"banana"` and
the test would still pass. Coverage without meaningful assertions is theater.

<br />

**What metrics to watch instead:**

<br />

> * **Mutation testing**: Tools like Stryker modify your code (change `+` to `-`, remove conditionals) and check if any tests fail. If a mutation survives, your tests have a blind spot. This is far more meaningful than line coverage.
> * **Branch coverage over line coverage**: Branch coverage catches untested conditional paths. A function with an if/else might have 100% line coverage but only 50% branch coverage if you never test the else path.
> * **Test failure rate in CI**: If tests never fail, they might not be testing anything meaningful. If they fail constantly, they might be flaky. A healthy test suite fails occasionally when real bugs are introduced.
> * **Time to detection**: How quickly do tests catch a real bug after it is introduced? This is the metric that actually matters for DevOps.

<br />

A reasonable coverage target is somewhere between 70% and 90%. Anything above 90% usually means you
are writing tests for trivial code just to hit a number.

<br />

##### **When to NOT write tests**
Testing everything is not the goal. Testing the right things is. Here are cases where writing tests
adds cost without meaningful value:

<br />

> * **Generated code**: If a tool generates your API client, ORM models, or GraphQL types, do not test the generation output. Test the code that uses them.
> * **Simple getters and setters**: A function that just returns a property does not need a test. If you feel the need to test it, the function is probably too simple to break.
> * **Framework internals**: Do not test that Express routes requests or that React renders components. Those are the framework's job. Test your logic that runs inside the framework.
> * **Third-party libraries**: Do not test that `lodash.groupBy` works correctly. The library maintainers already did that.
> * **Configuration files**: JSON configs, environment variable listings, and static data do not need unit tests.

<br />

Focus your testing effort where bugs are most likely and most expensive: business logic, data
transformations, edge cases in parsing, and integration points between systems.

<br />

##### **Running tests in CI**
We will cover CI/CD in detail in the next article, but here is a preview of what running tests in
GitHub Actions looks like:

<br />

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - run: npm test

      - run: npm run test:coverage

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
```

<br />

This workflow runs on every push and pull request. If any test fails, the CI run fails and the PR
cannot be merged (assuming you have branch protection enabled). This is the gate we talked about
earlier: code does not reach production unless it passes the tests.

<br />

Key things to notice:

<br />

> * **`npm ci`** instead of `npm install`: this installs exact versions from `package-lock.json`, ensuring reproducible builds.
> * **Separate test and coverage steps**: run tests first for fast feedback, then coverage as a separate step.
> * **Upload artifacts**: coverage reports are saved so you can download and review them later.

<br />

We will expand on this significantly in article five, covering caching, matrix builds, parallel test
execution, and more.

<br />

##### **Putting it all together**
Let's review what a well-tested project looks like. Here is the full directory structure:

<br />

```
testing-demo/
  package.json
  tsconfig.json
  src/
    utils.ts              # Pure utility functions
    utils.test.ts         # Unit tests for utils
    weather.ts            # Module with external dependency
    weather.test.ts       # Unit tests with mocks
    app.ts                # Express application
    app.test.ts           # Integration tests with Supertest
```

<br />

Each layer of the pyramid is covered:

<br />

> * **Unit tests** (`utils.test.ts`, `weather.test.ts`): Fast, isolated, no external dependencies. These catch logic bugs.
> * **Integration tests** (`app.test.ts`): Test the HTTP layer end to end (within the app). These catch wiring bugs.
> * **E2E tests** (not shown here): Would use a tool like Playwright or Cypress to test the full stack through a browser.

<br />

The testing workflow in a DevOps pipeline looks like this:

<br />

> 1. Developer pushes code.
> 2. CI runs unit tests (seconds).
> 3. CI runs integration tests (seconds to minutes).
> 4. CI runs E2E tests (minutes).
> 5. If all pass, the code is eligible for deployment.
> 6. If any fail, the pipeline stops and the developer is notified.

<br />

This is the fast feedback loop that makes DevOps work. You find bugs in minutes, not days.

<br />

##### **Closing notes**
Testing is not optional in a DevOps workflow. It is the foundation that makes everything else
possible: continuous integration, continuous deployment, and the confidence to ship changes multiple
times a day.

<br />

Start with unit tests. They are the cheapest and give you the most value per line of test code. Add
integration tests for your API endpoints and critical data flows. Use E2E tests sparingly for your
most important user journeys.

<br />

Do not chase coverage numbers. Focus on testing behavior that matters: business logic, edge cases,
and integration points. A well-placed test that catches a real bug is worth more than a hundred tests
that just inflate a coverage metric.

<br />

In the next article, we will take these tests and wire them into a proper CI/CD pipeline with GitHub
Actions. You will see how to run tests automatically, cache dependencies for speed, and set up branch
protection so untested code never reaches production.

<br />

Hope you found this useful and enjoyed reading it, until next time!

<br />

##### **Errata**
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [sources here](https://github.com/kainlite/tr)

<br />

---lang---
%{
  title: "DevOps from Zero to Hero: Testing Automatizado",
  author: "Gabriel Garrido",
  description: "Vamos a explorar la piramide de testing, escribir tests unitarios y de integracion con Vitest y Supertest, y discutir por que las metricas de cobertura pueden ser enganosas...",
  tags: ~w(devops typescript testing beginners),
  published: true,
  image: "devops.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introduccion**
Bienvenido al cuarto articulo de la serie DevOps from Zero to Hero. En los articulos anteriores
cubrimos los fundamentos de Linux, networking y control de versiones con Git. Ahora es momento de
hablar sobre algo que separa los proyectos hobby del software listo para produccion: el testing
automatizado.

<br />

Si alguna vez pusheaste un cambio a produccion e inmediatamente te arrepentiste, ya entendes por que
el testing importa. Los tests automatizados te dan confianza en que tu codigo funciona como se espera
antes de que llegue a los usuarios. En un contexto DevOps, los tests son la puerta entre "codigo
escrito" y "codigo deployado." Sin ellos, tu pipeline de CI/CD es simplemente una forma rapida de
enviar bugs.

<br />

En este articulo vamos a cubrir la piramide de testing, escribir tests unitarios y de integracion
reales en TypeScript usando Vitest y Supertest, hablar sobre lo que la cobertura realmente significa
(y por que perseguir el 100% es una trampa), y sentar las bases para correr tests en CI, que vamos
a cubrir en profundidad en el articulo cinco.

<br />

Vamos a meternos de lleno.

<br />

##### **Por que el testing importa para DevOps**
El testing no es solo una preocupacion del desarrollador. En un workflow de DevOps, los tests son la
base de todo lo demas que construis. Aca te explico por que:

<br />

> * **Confianza para deployar**: Si tus tests pasan, podes deployar sin miedo. Si no pasan, sabes que algo esta roto antes de que los usuarios se enteren.
> * **Feedback rapido**: Un buen suite de tests te dice en minutos si un cambio es seguro. Compara eso con esperar QA manual o enterarte por un reporte de usuario.
> * **Atrapar regresiones**: Codigo que funcionaba ayer se puede romper hoy por un cambio aparentemente no relacionado. Los tests atrapan estas regresiones automaticamente.
> * **Habilitar automatizacion**: Los pipelines de CI/CD dependen de tests. Sin tests automatizados, tu pipeline es solo deployment automatizado de codigo no testeado.
> * **Documentacion**: Tests bien escritos describen lo que tu codigo deberia hacer. Sirven como documentacion viva que se mantiene sincronizada con el comportamiento real.

<br />

Pensalo de esta manera: cada test que escribis es un pequenio contrato que dice "este comportamiento
debe preservarse." Cuando alguien cambie el codigo dentro de seis meses, esos contratos atrapan
cualquier cosa que se rompa. Eso es increiblemente valioso en un equipo donde multiples personas
tocan la misma base de codigo.

<br />

##### **La piramide de testing**
La piramide de testing es un modelo que te ayuda a decidir cuantos tests de cada tipo escribir. Se
ve asi:

<br />

```
        /  E2E  \          Pocos, lentos, caros
       /----------\
      / Integracion \      Algunos, velocidad moderada
     /----------------\
    /   Tests Unitarios \  Muchos, rapidos, baratos
   /____________________\
```

<br />

La forma importa. Aca te explico por que:

<br />

> * **Tests unitarios** (base de la piramide): Testean funciones o modulos individuales de forma aislada. Son rapidos, baratos de escribir y baratos de correr. Deberias tener la mayor cantidad de estos.
> * **Tests de integracion** (medio): Testean como funcionan multiples piezas juntas, como un endpoint de API que consulta una base de datos. Son mas lentos y complejos, pero atrapan problemas que los tests unitarios no detectan.
> * **Tests end-to-end** (cima): Testean la aplicacion completa desde la perspectiva del usuario, generalmente a traves de un navegador. Son los mas lentos, fragiles y caros de mantener. Deberias tener la menor cantidad de estos.

<br />

La forma de piramide existe por un tradeoff entre velocidad y confianza. Los tests unitarios corren
en milisegundos pero solo testean piezas pequenias. Los tests E2E toman segundos o minutos pero
testean el flujo completo. Si invertis la piramide (muchos E2E, pocos unitarios), tu suite de tests
se vuelve lento, fragil y doloroso de mantener.

<br />

Una proporcion saludable podria verse algo asi como 70% unitarios, 20% integracion, 10% E2E. Estos
numeros no son reglas, son guias. La clave es: empuja el testing hacia el nivel mas bajo que te de
confianza. Si podes atrapar un bug con un test unitario, no escribas un test E2E para eso.

<br />

##### **Configurando el proyecto**
Vamos a armar un pequenio proyecto TypeScript con tests. Vamos a usar Vitest como nuestro test runner
porque es rapido, moderno y funciona genial con TypeScript sin configuracion extra.

<br />

Primero, inicializa el proyecto:

<br />

```bash
mkdir testing-demo && cd testing-demo
npm init -y
npm install -D typescript vitest @types/node
npm install express
npm install -D @types/express supertest @types/supertest
```

<br />

Crea un `tsconfig.json`:

<br />

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "outDir": "./dist",
    "rootDir": "./src",
    "declaration": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

<br />

Agrega el script de test al `package.json`:

<br />

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage"
  }
}
```

<br />

##### **Tests unitarios con Vitest**
Empecemos por la base de la piramide. Los tests unitarios verifican que las funciones individuales
hagan lo que se supone que deben hacer. Deben ser rapidos, aislados y deterministas.

<br />

Aca hay un modulo de utilidades simple en `src/utils.ts`:

<br />

```typescript
// src/utils.ts

export function slugify(text: string): string {
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, "")
    .replace(/[\s_]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

export function truncate(text: string, maxLength: number): string {
  if (text.length <= maxLength) {
    return text;
  }
  const truncated = text.slice(0, maxLength);
  const lastSpace = truncated.lastIndexOf(" ");
  if (lastSpace > 0) {
    return truncated.slice(0, lastSpace) + "...";
  }
  return truncated + "...";
}

export function parseQueryParams(query: string): Record<string, string> {
  if (!query || query.trim() === "") {
    return {};
  }
  const cleaned = query.startsWith("?") ? query.slice(1) : query;
  return cleaned.split("&").reduce(
    (params, pair) => {
      const [key, value] = pair.split("=");
      if (key) {
        params[decodeURIComponent(key)] = decodeURIComponent(value ?? "");
      }
      return params;
    },
    {} as Record<string, string>,
  );
}
```

<br />

Ahora escribamos los tests en `src/utils.test.ts`:

<br />

```typescript
// src/utils.test.ts
import { describe, it, expect } from "vitest";
import { slugify, truncate, parseQueryParams } from "./utils";

describe("slugify", () => {
  it("converts a simple string to a slug", () => {
    expect(slugify("Hello World")).toBe("hello-world");
  });

  it("handles special characters", () => {
    expect(slugify("Hello, World! How's it going?")).toBe(
      "hello-world-hows-it-going",
    );
  });

  it("collapses multiple spaces and dashes", () => {
    expect(slugify("too   many   spaces")).toBe("too-many-spaces");
    expect(slugify("too---many---dashes")).toBe("too-many-dashes");
  });

  it("trims leading and trailing dashes", () => {
    expect(slugify("  -hello-  ")).toBe("hello");
  });

  it("handles empty string", () => {
    expect(slugify("")).toBe("");
  });
});

describe("truncate", () => {
  it("returns the full string if it is shorter than maxLength", () => {
    expect(truncate("short", 10)).toBe("short");
  });

  it("returns the full string if it equals maxLength", () => {
    expect(truncate("exact", 5)).toBe("exact");
  });

  it("truncates at the last space before maxLength", () => {
    expect(truncate("this is a longer sentence", 15)).toBe("this is a...");
  });

  it("truncates without space if no space is found", () => {
    expect(truncate("superlongwordwithoutspaces", 10)).toBe(
      "superlongw...",
    );
  });
});

describe("parseQueryParams", () => {
  it("parses a simple query string", () => {
    expect(parseQueryParams("name=alice&age=30")).toEqual({
      name: "alice",
      age: "30",
    });
  });

  it("handles a leading question mark", () => {
    expect(parseQueryParams("?foo=bar")).toEqual({ foo: "bar" });
  });

  it("handles URL-encoded values", () => {
    expect(parseQueryParams("msg=hello%20world")).toEqual({
      msg: "hello world",
    });
  });

  it("returns an empty object for empty input", () => {
    expect(parseQueryParams("")).toEqual({});
  });

  it("handles keys without values", () => {
    expect(parseQueryParams("flag=")).toEqual({ flag: "" });
  });
});
```

<br />

Desglosemos la estructura de los tests:

<br />

> * **`describe`** agrupa tests relacionados. Pensalo como un encabezado de seccion para un conjunto de comportamientos.
> * **`it`** define un caso de test individual. El string deberia leerse como una oracion: "it converts a simple string to a slug."
> * **`expect`** es la asercion. Toma un valor y encadena un matcher como `toBe`, `toEqual`, `toContain`, o `toThrow`.

<br />

Corre los tests:

<br />

```bash
npx vitest run

# Output:
# ✓ src/utils.test.ts (10 tests) 5ms
#   ✓ slugify (5 tests)
#   ✓ truncate (4 tests)
#   ✓ parseQueryParams (5 tests)
# Test Files  1 passed (1)
# Tests       14 passed (14)
```

<br />

##### **Mockeando dependencias**
El codigo del mundo real tiene dependencias: bases de datos, APIs, sistemas de archivos. En los tests
unitarios, queres aislar la funcion bajo test reemplazando esas dependencias con sustitutos
controlados. Esto se llama mocking.

<br />

Aca hay un modulo que depende de una API externa en `src/weather.ts`:

<br />

```typescript
// src/weather.ts

export interface WeatherData {
  city: string;
  temperature: number;
  description: string;
}

export async function fetchWeather(city: string): Promise<WeatherData> {
  const response = await fetch(
    `https://api.weather.example.com/v1/current?city=${encodeURIComponent(city)}`,
  );
  if (!response.ok) {
    throw new Error(`Weather API returned ${response.status}`);
  }
  const data = await response.json();
  return {
    city: data.location.name,
    temperature: data.current.temp_c,
    description: data.current.condition.text,
  };
}

export function formatWeatherReport(weather: WeatherData): string {
  return `${weather.city}: ${weather.temperature}C, ${weather.description}`;
}
```

<br />

Y los tests en `src/weather.test.ts`:

<br />

```typescript
// src/weather.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { fetchWeather, formatWeatherReport } from "./weather";

// Mockear la funcion global fetch
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
});

describe("fetchWeather", () => {
  it("returns parsed weather data on success", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        location: { name: "London" },
        current: { temp_c: 15, condition: { text: "Partly cloudy" } },
      }),
    });

    const result = await fetchWeather("London");

    expect(result).toEqual({
      city: "London",
      temperature: 15,
      description: "Partly cloudy",
    });
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.weather.example.com/v1/current?city=London",
    );
  });

  it("throws on non-ok response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    await expect(fetchWeather("Nowhere")).rejects.toThrow(
      "Weather API returned 404",
    );
  });
});

describe("formatWeatherReport", () => {
  it("formats the weather data as a readable string", () => {
    const weather = {
      city: "Berlin",
      temperature: 22,
      description: "Sunny",
    };
    expect(formatWeatherReport(weather)).toBe("Berlin: 22C, Sunny");
  });
});
```

<br />

Conceptos clave de mocking:

<br />

> * **`vi.fn()`** crea una funcion mock que registra como fue llamada.
> * **`vi.stubGlobal()`** reemplaza un global como `fetch` con tu mock.
> * **`mockResolvedValueOnce()`** le dice al mock que devolver la proxima vez que sea llamado.
> * **`mockReset()`** limpia el estado del mock entre tests para que no se filtren entre si.

<br />

Lo importante de entender sobre mocking es esto: no estas testeando `fetch`. Estas testeando que tu
codigo maneje correctamente la respuesta de `fetch`. El mock te deja simular diferentes escenarios
(exito, error, timeout) sin hacer llamadas de red reales.

<br />

##### **Tests de integracion con Supertest**
Los tests de integracion verifican que multiples piezas de tu aplicacion funcionen juntas. Para
aplicaciones web, el test de integracion mas comun es pegarle a un endpoint de API y verificar la
respuesta.

<br />

Aca hay una app Express simple en `src/app.ts`:

<br />

```typescript
// src/app.ts
import express from "express";
import { slugify, truncate } from "./utils";

export const app = express();

app.use(express.json());

interface Article {
  id: number;
  title: string;
  slug: string;
  content: string;
  summary?: string;
}

const articles: Article[] = [];
let nextId = 1;

app.get("/api/articles", (_req, res) => {
  res.json(articles);
});

app.get("/api/articles/:slug", (req, res) => {
  const article = articles.find((a) => a.slug === req.params.slug);
  if (!article) {
    res.status(404).json({ error: "Article not found" });
    return;
  }
  res.json(article);
});

app.post("/api/articles", (req, res) => {
  const { title, content } = req.body;
  if (!title || !content) {
    res.status(400).json({ error: "Title and content are required" });
    return;
  }
  const article: Article = {
    id: nextId++,
    title,
    slug: slugify(title),
    content,
    summary: truncate(content, 100),
  };
  articles.push(article);
  res.status(201).json(article);
});

app.delete("/api/articles/:slug", (req, res) => {
  const index = articles.findIndex((a) => a.slug === req.params.slug);
  if (index === -1) {
    res.status(404).json({ error: "Article not found" });
    return;
  }
  articles.splice(index, 1);
  res.status(204).send();
});
```

<br />

Ahora los tests de integracion en `src/app.test.ts`:

<br />

```typescript
// src/app.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { app } from "./app";

describe("Articles API", () => {
  describe("POST /api/articles", () => {
    it("creates a new article", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({
          title: "My First Post",
          content:
            "This is the content of my first blog post. It has enough words to test truncation properly.",
        })
        .expect(201);

      expect(response.body).toMatchObject({
        title: "My First Post",
        slug: "my-first-post",
        content:
          "This is the content of my first blog post. It has enough words to test truncation properly.",
      });
      expect(response.body.id).toBeDefined();
      expect(response.body.summary).toBeDefined();
    });

    it("returns 400 when title is missing", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({ content: "some content" })
        .expect(400);

      expect(response.body.error).toBe("Title and content are required");
    });

    it("returns 400 when content is missing", async () => {
      const response = await request(app)
        .post("/api/articles")
        .send({ title: "A Title" })
        .expect(400);

      expect(response.body.error).toBe("Title and content are required");
    });
  });

  describe("GET /api/articles", () => {
    it("returns the list of articles", async () => {
      const response = await request(app).get("/api/articles").expect(200);

      expect(Array.isArray(response.body)).toBe(true);
      expect(response.body.length).toBeGreaterThan(0);
    });
  });

  describe("GET /api/articles/:slug", () => {
    it("returns an article by slug", async () => {
      const response = await request(app)
        .get("/api/articles/my-first-post")
        .expect(200);

      expect(response.body.slug).toBe("my-first-post");
      expect(response.body.title).toBe("My First Post");
    });

    it("returns 404 for a non-existent slug", async () => {
      const response = await request(app)
        .get("/api/articles/does-not-exist")
        .expect(404);

      expect(response.body.error).toBe("Article not found");
    });
  });

  describe("DELETE /api/articles/:slug", () => {
    it("deletes an article by slug", async () => {
      await request(app)
        .post("/api/articles")
        .send({ title: "To Be Deleted", content: "This will be removed" });

      await request(app)
        .delete("/api/articles/to-be-deleted")
        .expect(204);

      await request(app)
        .get("/api/articles/to-be-deleted")
        .expect(404);
    });

    it("returns 404 when deleting a non-existent article", async () => {
      await request(app)
        .delete("/api/articles/ghost-article")
        .expect(404);
    });
  });
});
```

<br />

Nota como los tests de integracion difieren de los unitarios:

<br />

> * **Testean el ciclo completo de request/response**, no solo una funcion.
> * **Ejercitan multiples capas** (routing, validacion, logica de negocio) juntas.
> * **Son mas lentos** porque levantan la capa HTTP, pero atrapan bugs que los tests unitarios no pueden, como definiciones de rutas incorrectas o middleware faltante.

<br />

Supertest es excelente porque no necesita que levantes el servidor en un puerto. Se engancha
directamente en Express, asi que los tests son rapidos y no entran en conflicto entre si.

<br />

##### **Testeando contra bases de datos reales con Testcontainers**
Para aplicaciones que usan base de datos, tenes que decidir: mockeas la base de datos o usas una
real? Mockear es mas rapido pero puede esconder bugs relacionados con sintaxis SQL, constraints o
comportamiento de queries. Testcontainers te da lo mejor de los dos mundos levantando una base de
datos real en Docker para tus tests.

<br />

Asi se ve usar Testcontainers conceptualmente:

<br />

```typescript
// src/db.integration.test.ts (ejemplo conceptual)
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PostgreSqlContainer } from "@testcontainers/postgresql";
import { Client } from "pg";

describe("Database integration", () => {
  let container: any;
  let client: Client;

  beforeAll(async () => {
    // Levantar un contenedor real de PostgreSQL
    container = await new PostgreSqlContainer("postgres:16")
      .withDatabase("testdb")
      .start();

    client = new Client({
      connectionString: container.getConnectionUri(),
    });
    await client.connect();

    // Correr migraciones
    await client.query(`
      CREATE TABLE articles (
        id SERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        slug TEXT UNIQUE NOT NULL,
        content TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
  }, 60000); // Los contenedores pueden tardar un momento en arrancar

  afterAll(async () => {
    await client.end();
    await container.stop();
  });

  it("inserts and retrieves an article", async () => {
    await client.query(
      "INSERT INTO articles (title, slug, content) VALUES ($1, $2, $3)",
      ["Test Article", "test-article", "Some content"],
    );

    const result = await client.query(
      "SELECT * FROM articles WHERE slug = $1",
      ["test-article"],
    );

    expect(result.rows).toHaveLength(1);
    expect(result.rows[0].title).toBe("Test Article");
  });
});
```

<br />

Testcontainers es especialmente util porque:

<br />

> * **Los tests corren contra el mismo motor de base de datos** que usas en produccion, atrapando bugs especificos del driver.
> * **Cada suite de tests obtiene un contenedor fresco**, asi que los tests no interfieren entre si.
> * **Funciona en CI** siempre que Docker este disponible (que generalmente lo esta en GitHub Actions).
> * **Sin base de datos compartida de tests** que acumule datos viejos o cause tests flaky por ejecuciones en paralelo.

<br />

El tradeoff es velocidad: arrancar un contenedor toma algunos segundos. Por esta razon, los tests
con Testcontainers pertenecen al nivel de integracion, no al nivel unitario.

<br />

##### **Convenciones de nombres y organizacion de tests**
Como nombras y organizas los tests importa mas de lo que pensarias. En seis meses, cuando un test
falle en CI, el nombre del test es lo primero que vas a ver. Un buen nombre te dice exactamente que
se rompio sin necesidad de leer el codigo.

<br />

Aca van algunas convenciones que funcionan bien:

<br />

**Organizacion de archivos:**

<br />

```
src/
  utils.ts
  utils.test.ts        # Co-ubicado con el archivo fuente
  app.ts
  app.test.ts
  weather.ts
  weather.test.ts
```

<br />

Co-ubicar los tests con los archivos fuente hace obvio que archivo cubre cada test. Algunos equipos
prefieren un directorio `__tests__` separado, pero la co-ubicacion tiene la ventaja de que cuando
renombras o moves un archivo, el test se mueve con el.

<br />

**Patrones de nombres:**

<br />

```typescript
// Bueno: Describe el comportamiento claramente
describe("slugify", () => {
  it("converts spaces to dashes", () => {});
  it("removes special characters", () => {});
  it("handles empty string", () => {});
});

// Malo: Vago o enfocado en la implementacion
describe("slugify", () => {
  it("works", () => {});
  it("test 1", () => {});
  it("uses regex", () => {}); // a quien le importa la implementacion?
});
```

<br />

El nombre del test deberia responder: "Que comportamiento verifica este test?" Cuando falla, la
salida deberia leerse como un reporte de bug: `slugify > removes special characters: FAILED`.

<br />

##### **Que significa realmente la cobertura**
La cobertura de codigo mide que porcentaje de tu codigo se ejecuta cuando corren tus tests. Podes
generar un reporte de cobertura con Vitest:

<br />

```bash
npx vitest run --coverage
```

<br />

Esto te da metricas como:

<br />

> * **Cobertura de lineas**: Que porcentaje de lineas fueron ejecutadas?
> * **Cobertura de ramas**: Que porcentaje de caminos if/else fueron tomados?
> * **Cobertura de funciones**: Que porcentaje de funciones fueron llamadas?
> * **Cobertura de sentencias**: Que porcentaje de sentencias fueron ejecutadas?

<br />

Un reporte de cobertura podria verse asi:

<br />

```bash
# ------------------|---------|----------|---------|---------|
# File              | % Stmts | % Branch | % Funcs | % Lines |
# ------------------|---------|----------|---------|---------|
# src/utils.ts      |   100   |   100    |   100   |   100   |
# src/weather.ts    |    85   |    75    |   100   |    85   |
# src/app.ts        |    92   |    80    |   100   |    92   |
# ------------------|---------|----------|---------|---------|
```

<br />

**Por que el 100% de cobertura es una trampa:**

<br />

La cobertura te dice que codigo fue ejecutado, no que codigo fue testeado correctamente. Considera
esto:

<br />

```typescript
// Este test tiene 100% de cobertura de la funcion add
function add(a: number, b: number): number {
  return a + b;
}

it("covers the add function", () => {
  add(1, 2); // Mira, la llamamos! 100% de cobertura!
  // Pero nunca verificamos el resultado...
});
```

<br />

Ese test ejecuta cada linea de `add` pero no prueba nada. La funcion podria devolver `"banana"` y
el test seguiria pasando. Cobertura sin aserciones significativas es puro teatro.

<br />

**Que metricas mirar en su lugar:**

<br />

> * **Mutation testing**: Herramientas como Stryker modifican tu codigo (cambian `+` por `-`, eliminan condicionales) y verifican si algun test falla. Si una mutacion sobrevive, tus tests tienen un punto ciego. Esto es mucho mas significativo que la cobertura de lineas.
> * **Cobertura de ramas sobre cobertura de lineas**: La cobertura de ramas atrapa caminos condicionales no testeados. Una funcion con un if/else puede tener 100% de cobertura de lineas pero solo 50% de cobertura de ramas si nunca testeas el camino else.
> * **Tasa de falla de tests en CI**: Si los tests nunca fallan, puede que no esten testeando nada significativo. Si fallan constantemente, puede que sean flaky. Un suite de tests saludable falla ocasionalmente cuando se introducen bugs reales.
> * **Tiempo de deteccion**: Que tan rapido los tests atrapan un bug real despues de que se introduce? Esta es la metrica que realmente importa para DevOps.

<br />

Un objetivo razonable de cobertura esta en algun lugar entre 70% y 90%. Cualquier cosa arriba de
90% generalmente significa que estas escribiendo tests para codigo trivial solo para alcanzar un
numero.

<br />

##### **Cuando NO escribir tests**
Testear todo no es el objetivo. Testear las cosas correctas si lo es. Aca hay casos donde escribir
tests agrega costo sin valor significativo:

<br />

> * **Codigo generado**: Si una herramienta genera tu cliente de API, modelos de ORM o tipos de GraphQL, no testees la salida generada. Testea el codigo que los usa.
> * **Getters y setters simples**: Una funcion que solo devuelve una propiedad no necesita test. Si sentis la necesidad de testearla, la funcion probablemente es demasiado simple para romperse.
> * **Internos del framework**: No testees que Express rutea requests o que React renderiza componentes. Ese es el trabajo del framework. Testea tu logica que corre dentro del framework.
> * **Librerias de terceros**: No testees que `lodash.groupBy` funciona correctamente. Los mantenedores de la libreria ya lo hicieron.
> * **Archivos de configuracion**: Configs JSON, listados de variables de entorno y datos estaticos no necesitan tests unitarios.

<br />

Enfoca tu esfuerzo de testing donde los bugs son mas probables y mas caros: logica de negocio,
transformaciones de datos, edge cases en parsing y puntos de integracion entre sistemas.

<br />

##### **Corriendo tests en CI**
Vamos a cubrir CI/CD en detalle en el proximo articulo, pero aca hay un preview de como se ve correr
tests en GitHub Actions:

<br />

```yaml
# .github/workflows/test.yml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          cache: "npm"

      - run: npm ci

      - run: npm test

      - run: npm run test:coverage

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage/
```

<br />

Este workflow corre en cada push y pull request. Si algun test falla, la ejecucion de CI falla y el
PR no se puede mergear (asumiendo que tenes branch protection habilitado). Esta es la puerta de la
que hablamos antes: el codigo no llega a produccion a menos que pase los tests.

<br />

Cosas clave para notar:

<br />

> * **`npm ci`** en vez de `npm install`: instala versiones exactas del `package-lock.json`, asegurando builds reproducibles.
> * **Pasos separados de test y coverage**: corre los tests primero para feedback rapido, despues coverage como paso separado.
> * **Subir artifacts**: los reportes de cobertura se guardan para que puedas descargarlos y revisarlos despues.

<br />

Vamos a expandir esto significativamente en el articulo cinco, cubriendo caching, matrix builds,
ejecucion paralela de tests, y mas.

<br />

##### **Juntando todo**
Repasemos como se ve un proyecto bien testeado. Aca esta la estructura completa de directorios:

<br />

```
testing-demo/
  package.json
  tsconfig.json
  src/
    utils.ts              # Funciones de utilidad puras
    utils.test.ts         # Tests unitarios para utils
    weather.ts            # Modulo con dependencia externa
    weather.test.ts       # Tests unitarios con mocks
    app.ts                # Aplicacion Express
    app.test.ts           # Tests de integracion con Supertest
```

<br />

Cada capa de la piramide esta cubierta:

<br />

> * **Tests unitarios** (`utils.test.ts`, `weather.test.ts`): Rapidos, aislados, sin dependencias externas. Estos atrapan bugs de logica.
> * **Tests de integracion** (`app.test.ts`): Testean la capa HTTP de punta a punta (dentro de la app). Estos atrapan bugs de cableado.
> * **Tests E2E** (no mostrados aca): Usarian una herramienta como Playwright o Cypress para testear el stack completo a traves de un navegador.

<br />

El workflow de testing en un pipeline de DevOps se ve asi:

<br />

> 1. El desarrollador pushea codigo.
> 2. CI corre tests unitarios (segundos).
> 3. CI corre tests de integracion (segundos a minutos).
> 4. CI corre tests E2E (minutos).
> 5. Si todos pasan, el codigo es elegible para deployment.
> 6. Si alguno falla, el pipeline se detiene y se notifica al desarrollador.

<br />

Este es el loop de feedback rapido que hace que DevOps funcione. Encontras bugs en minutos, no en
dias.

<br />

##### **Notas de cierre**
El testing no es opcional en un workflow de DevOps. Es la base que hace posible todo lo demas:
integracion continua, deployment continuo y la confianza para enviar cambios multiples veces al dia.

<br />

Empeza con tests unitarios. Son los mas baratos y te dan el mayor valor por linea de codigo de test.
Agrega tests de integracion para tus endpoints de API y flujos de datos criticos. Usa tests E2E con
moderacion para tus journeys de usuario mas importantes.

<br />

No persigas numeros de cobertura. Enfocate en testear comportamiento que importa: logica de negocio,
edge cases y puntos de integracion. Un test bien ubicado que atrapa un bug real vale mas que cien
tests que solo inflan una metrica de cobertura.

<br />

En el proximo articulo, vamos a tomar estos tests y conectarlos a un pipeline de CI/CD apropiado con
GitHub Actions. Vas a ver como correr tests automaticamente, cachear dependencias para velocidad y
configurar branch protection para que codigo no testeado nunca llegue a produccion.

<br />

Espero que te haya resultado util y que lo hayas disfrutado, hasta la proxima!

<br />

##### **Errata**
Si encontras algun error o tenes alguna sugerencia, mandame un mensaje para que se corrija.

Tambien podes revisar el codigo fuente y los cambios en los [fuentes aca](https://github.com/kainlite/tr)

<br />
