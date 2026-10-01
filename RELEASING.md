# Releasing veneer

Releases go to pub.dev and to GitHub as a tag and pre-release. Run every step from the repo root.

## 1. Make sure the version is free

```bash
curl -s https://pub.dev/api/packages/veneer | python3 -c "import json,sys; print(json.load(sys.stdin)['latest']['version'])"
git fetch --tags && git tag -l 'v*' | sort -V | tail -3
```

If pub.dev or a tag already has the version you're about to release, stop. pub.dev versions can't be
replaced or re-uploaded, and an existing tag must keep matching what pub.dev serves. Ship further
changes as the next patch version instead.

## 2. Review what's going out

```bash
git status --short
git diff
```

Read the whole diff, including changes you didn't make. Every change belongs under the new version in
`CHANGELOG.md`.

## 3. Set the version in three places

- `pubspec.yaml`: `version: X.Y.Z`
- `ios/veneer.podspec`: `s.version = 'X.Y.Z'`
- `CHANGELOG.md`: rename `## Unreleased` to `## X.Y.Z` (or add the section at the top)

## 4. Check

```bash
dart format --line-length 120 --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
(cd example && flutter pub get && flutter build ios --simulator --debug)
flutter pub publish --dry-run
```

The example build is what compiles the Swift code, so don't skip it after native changes. The dry run
should report only one warning: that there are uncommitted files.

## 5. Commit and publish

```bash
git add -A
git commit -m "<summary>; release X.Y.Z"
flutter pub publish --force
```

Publish before tagging. If the upload fails, nothing points at the commit yet, so you can fix it and
amend it.

## 6. Tag, push and create the GitHub release

```bash
git tag vX.Y.Z
git push origin HEAD --tags
awk '/^## X.Y.Z/{f=1;next}/^## /{f=0}f' CHANGELOG.md > /tmp/notes.md
gh release create vX.Y.Z --repo troyvnit/veneer --title "X.Y.Z" --notes-file /tmp/notes.md --prerelease
```

## 7. Confirm

```bash
curl -s https://pub.dev/api/packages/veneer | python3 -c "import json,sys; print(json.load(sys.stdin)['latest']['version'])"
```

The new version can take up to 10 minutes to appear. Apps that depend on it can only resolve it after
that.
