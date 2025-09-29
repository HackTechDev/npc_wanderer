return {
    start = {
        text = "Bienvenue au village !",
        options = {
            {"Qui es-tu ?", "who"},
            {"Des conseils ?", "tips"},
            {"À plus.", "bye"},
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

