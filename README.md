style-hint
===============

## Configs

Each of the sub-modules (JSCS, JSHint, and CoffeeLint) have their respective configs and rules stored in an property of their name inside [config.json](config.json).

## Usage

    node node_modules/.bin/style-hint [directory or file to parse]

## Flags

### --globals
--globals='window,document'

Allows you to add predefined variables to the JSHINT predef config for any global variables (separated by commas) you want to supress undefined errors for.

### --js

Will only process JS files, not Coffee files.

## --coffee

Will only process Coffee files, not JS files.

## --limit
--limit=10

Define the total amount of errors FOR EACH of the sub-modules to report. Default is 10.

## --no-char-limit

Suppress all errors regarding line character count