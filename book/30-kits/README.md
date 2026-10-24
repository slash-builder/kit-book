# Kits

This folder is a placeholder. The generated catalog and each Kit's reference pages will land here.

## What will be here

* **A catalog of every Kit in the registry.** It lists every Kit, including private, banked and archived ones, as status cards. Each card carries the Kit's name, a one-line tagline, its status, its language, a link to its repository **only if the Kit is public**, what it owns, and what it will not do.
* **One section per Kit** with its reference documentation: the narrative a newcomer needs and the reference an experienced user looks things up in.

The catalog is generated from the registry rather than written by hand, so it cannot drift from it. The hook that will generate it is `make docs-catalog`; it prints "catalog generation not implemented yet" today.

## What will not be here

This repository is the book, not a Kit. It does not appear in the registry or the catalog.

## Until then

The Kits the demo apps use are downloaded into `.kits/` by `make setup`, and each brings its own documentation. Two of the pages already in this book describe a Kit in use: the [demo apps guide](../20-guides/demo-apps.md) and [Fitting the Application Kit to other Kits](../20-guides/fitting-the-application-kit-to-other-kits.md).
