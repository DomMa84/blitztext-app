#!/usr/bin/env python3
"""Lists what is new in the original repository and not yet in this fork, as an issue
"Neu im Original" in the fork. Nothing is merged: you read it, tick what you want, and take
those changes over one by one (each as a pull request with CI).

    python3 scripts/upstream-check.py --dry-run    # print the issue instead of creating it

Runs every week in .github/workflows/upstream-check.yml. Needs git with the history of this
branch and, without --dry-run, the GitHub CLI (gh) with a token that may write issues.

Each issue ends with a marker naming the original's newest commit it covered; the next run
lists only what came after it. A change already taken over by cherry-pick is left out.
"""

import argparse
import json
import os
import re
import subprocess
import sys

UPSTREAM = os.environ.get("UPSTREAM_REPO", "cmagnussen/blitztext-app")
BRANCH = os.environ.get("UPSTREAM_BRANCH", "main")
LABEL = "upstream"
MARKER = re.compile(r"upstream-head: ([0-9a-f]{40})")
# GitHub takes up to 65,536 characters in an issue body.
MAX_BODY = 60_000
MAX_DESCRIPTION = 1_500
TRAILER = re.compile(r"^(co-authored-by|signed-off-by|claude-session):", re.IGNORECASE)


def run(*args, stdin=None):
    return subprocess.run(args, check=True, capture_output=True, text=True, input=stdin).stdout


def git(*args):
    return run("git", *args)


def is_commit(ref):
    return subprocess.run(["git", "cat-file", "-e", f"{ref}^{{commit}}"], capture_output=True).returncode == 0


def last_reviewed():
    """The original's commit the previous issue went up to, if there was one."""
    issues = json.loads(run("gh", "issue", "list", "--label", LABEL, "--state", "all", "--limit", "1", "--json", "body"))
    if not issues:
        return None
    match = MARKER.search(issues[0].get("body") or "")
    return match.group(1) if match else None


def new_commits(head, upstream, since):
    """Commits of the original whose change is not in `head` yet, oldest first."""
    pending = git("log", "--reverse", "--no-merges", "--cherry-pick", "--right-only", "--format=%H", f"{head}...{upstream}").split()
    if since and is_commit(since):
        after = set(git("rev-list", f"{since}..{upstream}").split())
        pending = [commit for commit in pending if commit in after]
    return pending


def release_tags(url):
    """Tags of the original by the commit they point at."""
    tags = {}
    for line in git("ls-remote", "--tags", url).splitlines():
        sha, ref = line.split("\t")
        # An annotated tag shows twice: as the tag object and, with ^{}, as its commit.
        # Only the commit can match, so both may go in.
        name = ref.removeprefix("refs/tags/").removesuffix("^{}")
        if name not in tags.get(sha, []):
            tags.setdefault(sha, []).append(name)
    return tags


def link_issues(text):
    """"(#80)" means the original's pull request, not one of this fork."""
    return re.sub(r"(?<![\w/])#(\d+)", rf"{UPSTREAM}#\1", text)


def describe(sha):
    subject, body, date = git("show", "-s", "--format=%s%x00%b%x00%cs", sha).split("\x00")
    # Trailers such as Co-authored-by say nothing about the change.
    lines = [line for line in body.strip().splitlines() if not TRAILER.match(line)]
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
    if len(text) > MAX_DESCRIPTION:
        text = text[:MAX_DESCRIPTION].rsplit("\n", 1)[0] + "\n…"
    day = "{2}.{1}.{0}".format(*date.strip().split("-"))
    return link_issues(subject.strip()), link_issues(text), day


def issue(commits, tags, upstream_head, owner):
    count = len(commits)
    versions = [name for sha in commits for name in tags.get(sha, [])]
    title = f"Neu im Original: {count} {'Änderung' if count == 1 else 'Änderungen'}"
    if versions:
        title += f" (Version {', '.join(versions)})"

    repo_url = f"https://github.com/{UPSTREAM}"
    parts = [
        f"Im Original [{UPSTREAM}]({repo_url}) gibt es **{count} "
        f"{'Änderung' if count == 1 else 'Änderungen'}**, die in diesem Fork noch fehlen. "
        "Übernommen wird nichts von selbst.",
    ]
    if versions:
        links = ", ".join(f"[{name}]({repo_url}/releases/tag/{name})" for name in versions)
        parts.append(f"**Neue Version:** {links}")
    parts.append(
        "Hake an, was du haben willst, und sag Claude: „Übernimm die angehakten aus diesem Issue.“ "
        "Jede Änderung kommt dann als eigener Pull Request mit Prüfung."
    )

    items = []
    for sha in commits:
        subject, text, day = describe(sha)
        item = f"- [ ] **{subject}** · {day} · [{sha[:7]}]({repo_url}/commit/{sha})"
        if text:
            indented = "\n".join(f"  {line}" if line else "" for line in text.splitlines())
            item += f"\n  <details><summary>Beschreibung</summary>\n\n{indented}\n\n  </details>"
        items.append(item)

    footer = []
    if owner:
        footer.append(f"@{owner}")
    footer.append(f"<!-- upstream-head: {upstream_head} -->")

    body = "\n\n".join(parts) + "\n\n" + "\n".join(items)
    room = MAX_BODY - len("\n\n".join(footer)) - 200
    if len(body) > room:
        body = body[:room].rsplit("\n- [ ]", 1)[0] + f"\n\n… und weitere, siehe [{UPSTREAM}/commits]({repo_url}/commits/{BRANCH})."
    return title, body + "\n\n" + "\n\n".join(footer)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="print the issue instead of creating it")
    parser.add_argument("--base", default="HEAD", help="the fork's branch to compare (default: HEAD)")
    parser.add_argument("--since", help="the original's commit already reviewed (default: from the last issue)")
    args = parser.parse_args()

    url = f"https://github.com/{UPSTREAM}.git"
    git("fetch", "--quiet", url, BRANCH)
    upstream_head = git("rev-parse", "FETCH_HEAD").strip()

    since = args.since
    if since is None and not args.dry_run:
        since = last_reviewed()

    commits = new_commits(args.base, upstream_head, since)
    if not commits:
        print(f"Nichts Neues im Original ({UPSTREAM}).")
        return 0

    title, body = issue(commits, release_tags(url), upstream_head, os.environ.get("GITHUB_REPOSITORY_OWNER"))
    if args.dry_run:
        print(title + "\n\n" + body)
        return 0

    run("gh", "label", "create", LABEL, "--color", "BB84DF", "--description", "Neues aus dem Original", "--force")
    print(run("gh", "issue", "create", "--title", title, "--label", LABEL, "--body-file", "-", stdin=body).strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
