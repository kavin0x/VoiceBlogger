CONTRIBUTING
============

Thanks for contributing to VoiceBlogger! This document explains how to report issues, propose changes, and set up a development environment so your contributions are easy to review and merge.

Getting started
---------------

- Fork the repository and create a feature branch from `main` named `feat/short-description` or `fix/short-description`.
- Keep commits small and focused. Use clear commit messages in the `form: type (scope)` `short description` (e.g. `fix(transcribe): handle empty input`).
Make sure to use [Conventional Commits]([text](https://www.conventionalcommits.org/en/v1.0.0/))

Development setup (Python)
--------------------------

1. Create and activate a virtual environment:

   python3 -m venv venv
   source venv/bin/activate

2. Install Python dependencies:

   pip install -r requirements.txt

3. Run or test the Python scripts (example):

   python Transcribe_and_blog.py

iOS development
----------------

- Open the Xcode workspace/project at `iOS App/VoiceBlogger/VoiceBlogger.xcodeproj` or the workspace in Xcode.
- Build and run on a simulator or device. Follow platform‑specific guidance in Xcode for signing and provisioning.

Code style and tests
--------------------

- Keep Python changes idiomatic and readable. Add or update tests where applicable. If you introduce new dependencies, add them to `requirements.txt`.
- For Swift, follow standard Swift style and prefer descriptive names. If you use linters (SwiftLint, etc.), include configuration and document installation.

Pull requests
-------------

- Open a PR from your feature branch to `main` with a clear title and description of the change.
- Explain the motivation, the approach, and any testing steps. Reference related issues using `#`.
- Keep PRs small when possible; large architectural changes benefit from a design discussion first (open an issue).

Reporting issues
----------------

- Use the repository Issues to report bugs or request features. Provide reproduction steps, expected vs actual behavior, and log excerpts if available.

Code of Conduct
---------------

Be respectful and considerate. If you don't already have a `CODE_OF_CONDUCT.md` in this repo, please follow common community standards for respectful collaboration. If you need a template, the Contributor Covenant is a good starting point.

Thank you
---------

Thanks for helping improve VoiceBlogger — your time and contributions are appreciated. If you want help getting started, open an issue and mention "help wanted" or ping the maintainers.
