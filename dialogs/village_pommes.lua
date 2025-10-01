return {
    start = {
        text = "Bienvenue au village !",
        options = {
            {"Qui es-tu ?", "who"},
            {"Des conseils ?", "tips"},
            {"Des pommes ?", "apples"},
            {"À plus.", "bye"},
        }
    },

    -- Nouvel écran : récupérer / échanger des pommes
    apples = {
        text = "Des pommes fraîches ! Tu veux en prendre ou faire un échange ?",
        options = {
            -- Don simple d'objets (nécessite les helpers d'actions ajoutés au mod)
            {"Une pomme (gratuite)", {give_item = "default:apple 1", msg = "Tiens, une pomme !", goto = "apples"}},
            {"5 pommes (gratuit)",   {give_items = {"default:apple 5"}, msg = "Voilà, 5 pommes.", goto = "apples"}},

            -- Petit trade : prend 5 bâtons et donne 3 pommes (annoté si indisponible)
            {"Échanger 5 bâtons → 3 pommes", {
                trade = {
                    take_items = {"default:stick 5"},
                    give_items = {"default:apple 3"},
                    msg = "Marché conclu : 3 pommes pour 5 bâtons."
                },
                goto = "apples"
            }},

            -- Variante : masquer l'option si le joueur n'a pas les items requis
            -- {"Échanger 99 bâtons → 1 pomme (caché si indispo)", {
            --     trade = { take_items = {"default:stick 99"}, give_items = {"default:apple 1"}, msg = "Merci !" },
            --     show_unavailable = false, goto = "apples"
            -- }},

            {"Retour", "start"},
            {"Fermer", "bye"},
        }
    },

    who = {
        text = "Je suis un humble villageois. Je me promène et je papote.",
        options = { {"Retour", "start"} }
    },

    tips = {
        text = "Pense à te faire un abri et à garder des torches.",
        options = { {"Encore un conseil", "tips2"}, {"Retour", "start"} }
    },

    tips2 = {
        text = "Garde de la nourriture et des outils sur toi. Bonne survie !",
        options = { {"Retour", "start"}, {"Fermer", "bye"} }
    },

    bye = { text = "À bientôt !", close = true }
}

