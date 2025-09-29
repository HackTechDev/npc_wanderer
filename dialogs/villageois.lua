return {
  start = {
    text = "Salut ! Je peux te donner des choses.",
    options = {
      {"Une pomme, stp", {goto="start", give_item="default:apple 1", msg="Tiens, une pomme."}},
      {"10 torches",     {give_item={name="default:torch", count=10}, close=true, msg="Torches livrées !"}},
      {"Un kit de départ", {
          give_items = {
            "default:pick_steel 1",
            {name="default:apple", count=5},
            {name="default:torch", count=20},
          },
          msg="Voilà le kit de départ.",
          -- msg_each="Reçu %COUNT%x %ITEM% (%HOW%)" -- optionnel, message par item
          goto="start"
      }},
      {"Au revoir", "bye"},
    }
  },
  bye = { text = "À plus !", close = true }
}

