# Elasticsearch Search Application

This application provides a UI for searching across one or more Elasticsearch indices.

## Concepts

### Web Components

This application is built using native Web Components as opposed to a third-party component framework like React, Vue, etc.

From [MDN](https://developer.mozilla.org/en-US/docs/Web/Web_Components):
> Web Components is a suite of different technologies allowing you to create reusable custom elements — with their functionality encapsulated away from the rest of your code — and utilize them in your web apps.

### Building

Since this application is implemented using native Web Components, any modern browser can render it as is,
requiring nothing more than a skeletal HTML file that imports the `src/components/Search.js` module and includes a `<search-app>` element.
See [index.html](https://github.com/CollectionBuilder/collectionbuilder-sa_draft/blob/bundle-search-app/_apps/search/index.html) for an example of how we do this for local development.

Serving the stock application in this way is great for local development, but is undesirable in production for the following reasons:
  - Inefficiencies
    - The browser makes a separate HTTP request to the server to retrieve each Javascript file
    - The Javascript files have not been minified (i.e. compressed)
  - Incompatibilites
    - Only browsers that support the HTML / Javascript features used in the application code will be able to render the application

In order to create a more compact and compatible version of our application, we need to build it. To do this, we'll use the [Open Web Components build tool](https://open-wc.org/docs/building/rollup/).

The build process comprises the following:

  1. Linting (optional)
  - This step (performed by [es-lint](https://eslint.org/)) checks the code against a set of style rules and emits a warning or error for each
  inconsistency that it finds.

  2. Prettifying (optional)
  - This step (performed by [prettier](https://prettier.io/)) reformats your code to conform with some preconceived notion of correctness.

  3. Transpiling
  - This step (performed by [rollup](https://rollupjs.org)) converts your modern, ES6 Javascript modules into code that's compatible with all modern browsers.

  4. Minifying
  - This step (performed by [rollup](https://rollupjs.org)) concatenates and compresses the multiple transpiled modules into a single file.


## Prerequisites

You'll need `node` (tested with v13.8.0) and `npm` (tested with v6.13.6) installed.

I recommend using [nvm](https://github.com/nvm-sh/nvm/blob/master/README.md) (node version manager) to install and manage your `node`/`npm` versions: [Installing and Updating](https://github.com/nvm-sh/nvm/blob/master/README.md#installing-and-updating)


## Install the Dependencies

Using a terminal, in the root directory of this application, execute:

```
npm install
```


## Available Commands

As reported by `npm run --list`:

```
Scripts available in  via `npm run-script`:
  lint:eslint
    eslint --ext .js,.html . --ignore-path .gitignore
  format:eslint
    eslint --ext .js,.html . --fix --ignore-path .gitignore
  lint:prettier
    prettier "**/*.js" --check --ignore-path .gitignore
  format:prettier
    prettier "**/*.js" --write --ignore-path .gitignore
  lint
    npm run lint:eslint && npm run lint:prettier
  format
    npm run format:eslint && npm run format:prettier
  build
    rimraf dist && rollup -c rollup.config.js
  start:build
    npm run build && web-dev-server --root-dir dist --app-index index.html --open --compatibility none
```

## Run the Linter (optional)

```
npm run lint:eslint
```

Any warnings and errors will be printed to the console.

If you want the let the linter automatically fix the things that it can, run:

```
npm run format:eslint
```


## Run the Prettifier (optional)

```
npm run lint:prettier
```

Whether or not each file complies with prettier's notion of correctness will be printed to the console.

If you want prettier to autmatically reformat your code as it sees fit, run:

```
npm run format:prettier
```


## Build the Application

```
npm run build
```

The built application will be written to the `dist/` directory as `<some-hash>.js`.

To use this application, import the Javascript file and instantiate the `<search-app>` element:

```
...
  <head>
    <script src="<path-to-<some-hash>.js>"></script>
  </head>

  <body>
    <search-app elasticsearch-url="<eleasticsearch-url>"
                elasticsearch-index="<elasticsearch-index-name>"
                fields="<comma-separated-list-of-document-fields>"
                faceted-fields="<comma-separated-list-of-document-fields-on-which-to-facet>"
                display-fields="<comma-separated-list-of-document-fields-to-display-for-each-item>">
    </search-app>
  </body>
...
```


## Build the Application and Start the Development Server

```
npm run start:build
```

A browser window will automatically launch that's pointed at the application.
