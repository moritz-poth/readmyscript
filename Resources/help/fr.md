# Read my Script

Read my Script transforme le PDF d’un scénario en livre audio. Un narrateur lit l’action, et chaque rôle parle avec sa propre voix. Les voix viennent de **VoiceStudio**, qui fonctionne sur le même Mac.

## Votre scénario reste sur ce Mac

- Le scénario n’est transmis qu’à VoiceStudio sur cet ordinateur (adresse 127.0.0.1) – jamais à Internet.
- La seule connexion à Internet est la question posée à GitHub pour savoir s’il existe une nouvelle version de Read my Script. Elle ne contient rien de vos scénarios.
- Le fichier journal liste ce que l’app a fait, sans aucun texte de vos scénarios.
- Read my Script vous avertit quand les statistiques d’utilisation ou la synchronisation cloud de VoiceStudio sont activées. Désactivez-les dans VoiceStudio avant de lire un scénario.

## Avant de commencer

- Installez et ouvrez **VoiceStudio**. Le point en haut à droite devient vert quand il est prêt ; sinon cliquez sur **Ouvrir VoiceStudio**.
- Créez quelques voix dans VoiceStudio – ou créez-en de nouvelles depuis Read my Script (voir « Une nouvelle voix »).

## Ouvrir un scénario

Faites glisser le PDF d’un scénario sur la fenêtre, ou utilisez **Fichier → Ouvrir un PDF…** (⌘O). Read my Script reconnaît les en-têtes de scène, l’action, les noms des personnages, les didascalies entre parenthèses, les dialogues et les transitions – dans des scénarios issus de Final Draft, Fade In, Word et d’autres programmes, en allemand et en anglais. Les numéros de page et de scène, les en-têtes et les filigranes sont ignorés.

- Tout ce qui précède le premier en-tête de scène (page de titre, notes) n’est pas lu. La distribution indique combien de paragraphes cela représente.
- Les PDF composés de pages numérisées ne contiennent pas de texte et ne peuvent pas encore être lus.

## Distribution

La colonne de gauche liste le **Narrateur** et tous les rôles, du plus grand nombre de répliques au plus petit. Choisissez une voix pour chacun dans son menu ; ▶ fait entendre une réplique du rôle avec cette voix.

- **Une voix par rôle :** Read my Script n’attribue jamais de lui-même une voix à deux rôles. S’il y a plus de rôles que de voix, les rôles restants affichent **Choisir une voix**. Si vous choisissez une voix déjà utilisée, l’app vous demande confirmation – les auditeurs ne distinguent les rôles que par leur voix.
- **Ne pas lire** laisse volontairement un rôle de côté.
- Tant qu’un rôle n’a pas de voix, le livre audio ne peut pas être créé – ainsi aucune réplique ne disparaît sans que vous le sachiez.

## Une nouvelle voix

**Nouvelle voix…**, en bas de chaque menu de voix, crée une voix dans VoiceStudio à partir de quelques caractéristiques : genre, âge, hauteur et chuchotement. **Écouter** fait entendre la première réplique du rôle, **Autre variante** donne une autre voix avec les mêmes caractéristiques. **Enregistrer la voix** la conserve dans VoiceStudio et l’attribue au rôle.

## Vérifier le texte

La colonne de droite montre le scénario tel qu’il sera lu. Un clic droit sur un paragraphe permet de le faire **lire par le narrateur**, de **ne pas le lire**, ou de revenir à **comme détecté**.

## Créer le livre audio

Choisissez en bas la **langue des voix** (Automatique, allemand ou anglais), cliquez sur **Créer le livre audio…** et choisissez où l’enregistrer. Le résultat est un livre audio `.m4b` avec un chapitre par scène.

- La création est longue : environ sept fois la durée d’écoute sur un Mac Apple Silicon – un scénario de 90 minutes demande une dizaine d’heures. Laissez-la tourner la nuit.
- **Pause** arrête VoiceStudio ; les scènes terminées sont conservées, **Reprendre** continue là où cela s’est arrêté. **Annuler** abandonne le livre audio à moitié fait.

## Réglages

**Read my Script → Réglages…** (⌘,) :

- **Général :** aspect clair ou sombre, langue (l’app redémarre).
- **Mises à jour :** version, recherche de mises à jour, versions de test. Un avis en haut de la fenêtre propose les nouvelles versions ; l’installation redémarre l’app.
- **Assistance :** un autotest avec des scénarios de test inventés (rien n’est envoyé), le fichier journal, et un café si l’app vous plaît.
- **À propos :** version, licence et code source.
