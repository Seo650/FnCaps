# FnCaps

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [Українська](README.uk.md) | [Русский](README.ru.md) | Français | [Español](README.es.md) | [Deutsch](README.de.md)

FnCaps est une application de barre des menus pour macOS destinée à ceux qui utilisent trois sources de saisie ou plus et trouvent le passage de l'une à l'autre lent.

macOS offre une seule touche qui parcourt toutes les sources de saisie l'une après l'autre. Avec trois sources ou plus, vous appuyez jusqu'à ce que la langue voulue apparaisse, vérifiez la barre des menus, puis appuyez encore.

FnCaps répartit vos sources de saisie entre deux touches, Caps Lock et fn (🌐).

- Chaque touche a sa propre liste et ne change qu'à l'intérieur de celle-ci.
- Vous décidez quelle langue va sur quelle touche. Par exemple, l'anglais sur Caps Lock et vos autres langues sur fn.
- Une longue liste devient deux listes courtes. Avec les dispositions que FnCaps recommande, la langue voulue est à une ou deux pressions, et votre frappe n'est pas interrompue.
- Avec plus de langues, vous pouvez attribuer son propre raccourci à une source de saisie et y accéder directement.
- Caps Lock change sans délai. Maintenez-la pour activer ou désactiver Caps Lock comme d'habitude.

> **Premier lancement :** macOS bloque FnCaps une fois, car Apple ne l'a pas notariée. Ouvrez Réglages Système > Confidentialité et sécurité, puis cliquez sur Ouvrir quand même. Les étapes sont dans [Ouvrir quand même](#open-anyway).

> FnCaps est en développement précoce jusqu'à la version 1.0.

## Configuration requise

- macOS 14 Sonoma ou version ultérieure, Apple silicon ou Intel
- L'autorisation Accessibilité. FnCaps en a besoin pour détecter les pressions sur fn et Caps Lock.

## Installation

### Homebrew

```sh
brew install --cask Seo650/tap/fncaps
```

### GitHub Releases

1. Téléchargez le dernier `FnCaps-x.y.z.zip` depuis [Releases](https://github.com/Seo650/FnCaps/releases/latest).
2. Décompressez-le.
3. Placez `FnCaps.app` dans `/Applications`.

## Premier lancement

<a id="open-anyway"></a>

### Ouvrir quand même

FnCaps est signée avec son propre certificat et n'est pas notariée par Apple, macOS bloque donc le premier lancement. Cela se produit une seule fois.

1. Ouvrez FnCaps. macOS indique qu'il ne peut pas vérifier l'application. Cliquez sur OK.
2. Ouvrez Réglages Système > Confidentialité et sécurité.
3. Sous Sécurité, cliquez sur Ouvrir quand même.
4. Saisissez votre mot de passe ou utilisez Touch ID, puis cliquez sur Ouvrir.

Le bouton Ouvrir quand même n'apparaît qu'après un lancement bloqué et reste environ une heure. S'il a disparu, ouvrez FnCaps à nouveau. Si vous préférez la ligne de commande, ceci supprime le blocage :

```sh
xattr -dr com.apple.quarantine /Applications/FnCaps.app
```

### Configuration

Au premier lancement, FnCaps vous guide dans l'autorisation Accessibilité et la disposition des touches. FnCaps a besoin de cette autorisation pour détecter les pressions sur fn et Caps Lock. Vous pouvez tout modifier plus tard dans les réglages de FnCaps.

## Mises à jour

FnCaps vérifie l'existence d'une nouvelle version une fois par jour. Pour l'installer, ouvrez les réglages de FnCaps, allez dans À propos de FnCaps et cliquez sur Mettre à jour. Rien n'est installé tant que vous n'avez pas cliqué sur Mettre à jour. Les utilisateurs de Homebrew mettent à jour de la même façon.

Les mises à jour conservent l'autorisation Accessibilité, car chaque version est signée avec le même certificat.

## Ce que FnCaps envoie

FnCaps n'enregistre pas ce que vous tapez. Elle se connecte à internet dans deux cas.

- Vérification des mises à jour : une fois par jour, FnCaps interroge l'API GitHub pour connaître la dernière version. La requête contient la version de l'application et rien d'autre sur vous.
- Signaler un bug : rien n'est envoyé tant que vous n'avez pas cliqué sur Envoyer. Un rapport contient votre message, votre adresse e-mail si vous en saisissez une, les versions de l'application et de macOS, le modèle de Mac, le type de clavier, vos réglages FnCaps, vos sources de saisie, le journal d'activité récent et un numéro d'installation aléatoire utilisé uniquement pour la limite quotidienne. Il ne contient pas ce que vous tapez, ni les numéros de série, ni d'autres identifiants d'appareil. Vous pouvez tout lire avant l'envoi. Les rapports sont stockés dans un dépôt privé que seul le développeur peut lire.
- Limites des rapports : cinq rapports par jour pour chaque installation, et cinq par minute depuis une même adresse réseau.

## Limitations connues

- Champs de mot de passe : macOS conserve les champs de mot de passe en anglais, FnCaps ne change donc pas de langue dans ces champs, et maintenir Caps Lock n'active pas Caps Lock.
- Control+Space : ne change pas de source de saisie tant que FnCaps est active. Cela fonctionne à nouveau lorsque FnCaps est désactivée ou quittée.
- Voyant de Caps Lock : lorsque vous activez Caps Lock en maintenant la touche, le voyant de la touche reste éteint. Les majuscules sont saisies normalement.
- Indicateur de langue : lorsque vous appuyez vite sur les touches, le petit indicateur que macOS affiche près du curseur peut indiquer une autre langue que celle en cours. La barre des menus indique la bonne.
- Caractère en cours de composition : si un caractère coréen, japonais ou chinois est encore en cours de composition lorsque vous appuyez sur fn, ce caractère peut être perdu.
- Disposition anglaise : FnCaps traite ABC et U.S. comme de l'anglais. ABC – AZERTY et ABC – QWERTZ comptent comme du français et de l'allemand.
- Karabiner-Elements et gksdud : ces applications modifient les mêmes touches. Une règle Karabiner qui utilise `caps_lock` prend la touche avant que FnCaps ne la voie. FnCaps affiche un avertissement tant que l'une d'elles est en cours d'exécution.
- Non testé, censé fonctionner : débrancher et rebrancher un clavier externe, macOS 14 à 26, et des Macs autres qu'un MacBook Air Apple silicon.

## Récupération

Si Caps Lock cesse de fonctionner :

- Dans FnCaps, choisissez Rétablir les touches dans le menu de l'icône de la barre des menus, ou cliquez sur Rétablir maintenant dans Réglages > Général. Cela remet Caps Lock et le raccourci de source de saisie dans l'état où ils étaient avant FnCaps.
- Si FnCaps n'est pas en cours d'exécution, par exemple après un plantage, Caps Lock peut rester remappée et ne rien faire. Effacez le remappage dans Terminal, puis ouvrez FnCaps à nouveau :

  ```sh
  hidutil property --set '{"UserKeyMapping":[]}'
  ```

- Si vous avez cloné ce dépôt, le script efface le remappage et rétablit aussi le raccourci de source de saisie :

  ```sh
  scripts/caps-recover.sh --restore
  ```

Si Control+Space ne change toujours pas de source de saisie après avoir quitté FnCaps, vérifiez Réglages Système > Clavier > Raccourcis clavier > Sources de saisie > « Sélectionner la source de saisie précédente ». Rétablir les touches la remet dans l'état où elle était avant FnCaps.

## Désinstallation

Quittez d'abord FnCaps. La fermeture remet Caps Lock et le raccourci de source de saisie dans leur état précédent. Exécutez ensuite :

```sh
brew uninstall --cask fncaps
```

Ou placez `FnCaps.app` de `/Applications` dans la corbeille. Pour supprimer aussi les réglages, utilisez `brew uninstall --zap --cask fncaps`.

## Compiler depuis la source

```sh
swift build
scripts/build-app.sh
```

`scripts/build-app.sh` crée `build/FnCaps.app`. Elle signe avec le certificat « FnCaps Dev Local » lorsqu'il existe, et avec une signature ad hoc sinon. Avec une signature ad hoc, macOS redemande l'autorisation Accessibilité après chaque compilation. `scripts/make-local-identity.sh` crée le certificat local.

## Contribution

Les signalements et les demandes de fusion sont les bienvenus. L'application et ce README sont traduits en dix langues. La plupart des traductions n'ont pas été relues par des locuteurs natifs, les corrections de traduction sont donc particulièrement bienvenues.

## Licence

MIT. Voir [LICENSE](LICENSE).
