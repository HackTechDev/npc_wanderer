# npc_wander — PNJ errants + dialogues (Luanti / Minetest)

**npc_wander** ajoute deux types de PNJ simples pour Luanti (anciennement Minetest) :
- **NPC marcheur** : se balade aléatoirement, prend des dégâts, meurt avec effets.
- **NPC dialogué** : idem + petit **arbre de dialogue** via formspec, actions (don d’objets), et chargement d’arbres depuis fichiers **.lua** ou **.json**.

> Licence : **MIT** — Auteur : Vous + ChatGPT  
> Testé dans un environnement Luanti **5.13.x**.

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Installation](#installation)
- [Dépendances](#dépendances)
- [Objets et commandes](#objets-et-commandes)
- [Dialogues : structure](#dialogues--structure)
- [Actions de dialogue](#actions-de-dialogue)
- [Charger un arbre depuis un fichier](#charger-un-arbre-depuis-un-fichier)
- [Personnaliser l’interface (formspec)](#personnaliser-linterface-formspec)
- [Astuces & Dépannage](#astuces--dépannage)
- [API / Intégration](#api--intégration)
- [Feuille de route](#feuille-de-route)
- [Licence](#licence)

---

## Fonctionnalités

### PNJ « marcheur »
- Marche aléatoirement avec pauses (réglages `WALK_SPEED`, `IDLE_MIN/MAX`, `WALK_MIN/MAX`).
- Détection d’obstacles et de précipices rudimentaire.
- **Vulnérable** au groupe d’attaque `fleshy` (armes/outils).
- **Prend des dégâts**, petit **knockback** au coup, sons facultatifs (`player_damage`, `player_death`) et particules à la mort.
- **Texture** copiée automatiquement depuis le joueur qui l’a placé (ou `character.png` par défaut).
- Persistance (`static_save = true`).

### PNJ « dialogué »
- Toutes les capacités du marcheur, plus :
- **Dialogue au clic droit** via formspec (arbre de nœuds + options).
- **Bouton Fermer** fiable (`button_exit`) et gestion d’`ESC`.
- **Chargement d’arbres** depuis **.lua** (recommandé) ou **.json** (nécessite `secure.trusted_mods`).
- **Actions** sur options, dont **donner un item** / **plusieurs items**.

---

## Installation

1. Placez le dossier du mod (par ex. `npc_wander/`) dans :
   ```
   <chemin>/luanti-5.xx.x/mods/
   ```
2. Vérifiez que le mod est **activé** pour votre monde.
3. (Optionnel) créez le dossier pour vos dialogues :
   ```
   npc_wander/dialogs/
   ```

---

## Dépendances

- Aucune dépendance dure. Le mod détecte `player_api` si présent pour caler les animations de `character.b3d`.  
- Les sons `player_damage` / `player_death` proviennent généralement du jeu de base ; si absents, ils seront simplement ignorés.

---

## Objets et commandes

### Objets
- `npc_wander:spawner` — **Spawner de NPC (marcheur)**, texture = skin du placeur.
- `npc_wander:spawner_dialog` — **Spawner de NPC (dialogué)**, texture = skin du placeur.

### Commandes
- `/add_npc`  
  Ajoute un PNJ marcheur devant le joueur.
- `/add_npc_dialog [Titre]`  
  Ajoute un PNJ dialogué. `Titre` facul. (affiché en nametag).
- `/add_npc_dialog_file <lua|json> <fichier> [Titre]`  
  Ajoute un PNJ dialogué **en chargeant l’arbre** depuis un fichier `.lua` ou `.json`.

**Interaction** : clic droit sur un PNJ dialogué pour ouvrir la fenêtre de discussion.

---

## Dialogues : structure

Un **arbre de dialogue** est une table de nœuds. Chaque nœud a :
- `text` : texte affiché.
- `options` : liste d’options cliquables ; **chaque option** est au format :
  - `{"Texte du bouton", "id_noeud_suivant"}` *(format simple, rétro‑compatible)*  
  - ou `{"Texte du bouton", { ...actions... }}` *(format enrichi : voir ci‑dessous)*.
- `close = true` (optionnel) : ferme la fenêtre de dialogue.

Exemple minimal :
```lua
DEFAULT_DIALOG = {
  start = {
    text = "Salut ! Besoin de quelque chose ?",
    options = {
      {"Qui es‑tu ?", "who"},
      {"Rien, merci.", "bye"},
    }
  },
  who = { text = "Je suis un PNJ de démo.", options = {{"Retour","start"}} },
  bye = { text = "À plus !", close = true }
}
```

---

## Actions de dialogue

Les **options enrichies** permettent d’exécuter des actions **avant** de sauter vers un autre nœud.

Clé disponibles (toutes optionnelles) :
- `goto = "id_noeud"` : nœud vers lequel naviguer après action.
- `close = true` : fermer la fenêtre de dialogue.
- `give_item = "mod:item N"` **ou** `{name="mod:item", count=N, wear=0, meta={...}}` : donne **un** item.
- `give_items = { <spec1>, <spec2>, ... }` : donne **plusieurs** items (chaque spec est une chaîne `"mod:item N"` ou une table `{name=..., count=...}`).
- `msg = "texte"` : message joueur après les actions (ex. “Tu reçois : …”).
- `msg_each = "texte"` : message **pour chaque item** de `give_items`, avec substitutions `%%ITEM%%`, `%%COUNT%%`, `%%HOW%%` (où `%%HOW%%` vaut `added` si mis dans l’inventaire du joueur, `dropped` si déposé au sol faute de place).

### Exemples

**Une pomme, puis retour au début :**
```lua
{"Une pomme, stp", {goto="start", give_item="default:apple 1", msg="Tiens, une pomme."}}
```

**10 torches et fermeture immédiate :**
```lua
{"10 torches", {give_item={name="default:torch", count=10}, close=true, msg="Torches livrées !"}}
```

**Kit de départ (plusieurs items) :**
```lua
{"Un kit de départ", {
  give_items = {
    "default:pick_steel 1",
    {name="default:apple", count=5},
    {name="default:torch", count=20},
  },
  msg = "Voilà le kit de départ.",
  -- msg_each = "Reçu %COUNT%x %ITEM% (%HOW%)",
  goto = "start"
}}
```

> Remarques :  
> - Si l’inventaire du joueur est **plein**, les objets sont **déposés au sol** devant lui.  
> - Les options simples `{"Texte","id"}` continuent de fonctionner.

---

## Charger un arbre depuis un fichier

### Format **.lua** (recommandé)
Un fichier `.lua` doit **retourner** la table de l’arbre :

`npc_wander/dialogs/villageois.lua`
```lua
return {
  start = {
    text = "Bienvenue au village !",
    options = {
      {"Qui es‑tu ?", "who"},
      {"Des conseils ?", "tips"},
      {"À plus.", "bye"}
    }
  },
  who = { text = "Je suis un humble villageois.", options = {{"Retour","start"}} },
  tips = { text = "Fais-toi un abri et garde des torches.", options = {{"Retour","start"}} },
  bye = { text = "À bientôt !", close = true }
}
```

**Commande :**
```
/add_npc_dialog_file lua villageois.lua Villageois
```
> Les chemins relatifs sans `/` sont résolus automatiquement vers `npc_wander/dialogs/`.  
> Vous pouvez aussi fournir un chemin relatif au mod (`dialogs/monfichier.lua`) ou un chemin **absolu** (`/home/.../monfichier.lua`).

### Format **.json**
Nécessite un environnement *insecure* (lecture de fichier).  
Ajoutez dans `minetest.conf` :
```
secure.trusted_mods = npc_wander
```
(redémarrez ensuite)

`npc_wander/dialogs/marchand.json`
```json
{
  "start": {
    "text": "Salut voyageur ! Tu cherches quelque chose ?",
    "options": [
      ["Qui es-tu ?", "who"],
      ["Tu vends quoi ?", "wares"],
      ["Rien, merci.", "bye"]
    ]
  },
  "who": { "text": "Je suis un marchand itinérant.", "options": [["Retour", "start"]] },
  "wares": { "text": "Repasse plus tard !", "options": [["Retour", "start"]] },
  "bye": { "text": "Bon voyage !", "close": true }
}
```

**Commande :**
```
/add_npc_dialog_file json marchand.json Marchand
```

---

## Personnaliser l’interface (formspec)

La fenêtre par défaut est `size[8,6]`.  
Pour augmenter la **hauteur** (ex. `8`) dans `show_dialog_formspec` :
```lua
fs[#fs+1] = "size[8,8]"
-- Ajustez aussi la hauteur du textarea et la position de départ des boutons :
fs[#fs+1] = ("textarea[0.4,0.8;7.2,3.6;_txt;;%s]"):format(minetest.formspec_escape(text))
local y = 4.6
```

Le bouton de fermeture utilise `button_exit` ; le callback gère aussi `fields.quit` (touche **Échap**).

---

## Astuces & Dépannage

- **Le bouton “Fermer” ne ferme pas**  
  → Utilisez `button_exit[...]` et, côté serveur :
  ```lua
  if fields.quit or fields._close then ACTIVE_DIALOG[pname] = nil; return end
  ```

- **Erreur** `request_insecure_environment() instead` lors du chargement JSON  
  → Ajoutez `secure.trusted_mods = npc_wander` dans `minetest.conf` (ou le nom réel de votre mod), ou préférez un **fichier .lua**.

- **Erreur Lua “unexpected symbol near 'if'”**  
  → Ne collez **pas** des patchs *diff* (lignes `+`/`-`) directement dans `init.lua`. Remplacez les blocs indiqués **sans** les marqueurs.

- **Pas de son aux coups / à la mort**  
  → Les sons `player_damage` / `player_death` ne sont pas fournis par tous les jeux. Le mod fonctionne sans.

---

## API / Intégration

À l’exécution, chaque entité dialoguée possède :
- `lua._dialog_tree` : table courante de dialogue (modifiable à chaud).
- `lua._dialog_title` : titre affiché (nametag).

Exemple pour remplacer l’arbre d’un PNJ fraîchement spawné :
```lua
local obj = minetest.add_entity(pos, "npc_wander:npc_dialog")
local lua = obj and obj:get_luaentity()
if lua then
  lua._dialog_title = "Guide"
  obj:set_properties({nametag = lua._dialog_title})
  lua._dialog_tree = my_custom_tree
end
```

---

## Feuille de route

- Variables de contexte dans les dialogues (`%player%`, `%pos%`, etc.).
- Autres actions : téléportation, sons personnalisés, particules, démarrage de “quête”.
- Déplacements plus intelligents (éviter l’eau / suivre un chemin / suivre un joueur).
- Support i18n.

---

## Licence

**MIT** — Voir l’en‑tête des fichiers du mod.  
Crédits : *Vous + ChatGPT*.  
