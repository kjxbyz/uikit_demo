
get:
	fvm flutter pub get

outdated:
	fvm flutter pub outdated

clean: ## Cleans the environment
	fvm flutter clean
	make get

apk: ## Release Apk
	echo "╠ Releasing Apk..."
	fvm flutter build apk

ipa:
	echo "╠ Releasing to adhoc..."
	fvm flutter build ipa --no-codesign
