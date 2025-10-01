-- npc_wander — PNJ simple qui marche aléatoirement + PRÉND DES DÉGÂTS
-- Auteur : Vous + ChatGPT
-- Licence : MIT

local WALK_SPEED = 2.5          -- m/s
local IDLE_MIN, IDLE_MAX = 2, 6 -- secondes de pause
local WALK_MIN, WALK_MAX = 4, 9 -- secondes de marche
local STEP_INTERVAL = 0.2       -- logique IA toutes les 0.2 s
local GRAVITY = -9.81

-- Petites utilitaires
local function rand_yaw()
    return math.random() * math.pi * 2
end

local function is_walkable(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then return true end -- prudence : si non chargé, on considère bloqué
    local def = minetest.registered_nodes[node.name]
    return def and def.walkable
end

local function copy_textures_from_player(player)
    if player and player:is_player() then
        local props = player:get_properties() or {}
        if props.textures and #props.textures > 0 then
            -- Copie défensive
            local t = {}
            for i, v in ipairs(props.textures) do t[i] = v end
            return t
        end
    end
    return {"character.png"}
end

local function get_player_anims()
    -- Valeurs par défaut compatibles avec character.b3d (Minetest/Luanti Game)
    local anims = {
        stand = {x = 0,   y = 79,  speed = 25},
        sit   = {x = 81,  y = 160, speed = 25},
        lay   = {x = 162, y = 166, speed = 25},
        walk  = {x = 168, y = 187, speed = 30},
    }
    if rawget(_G, "player_api")
        and player_api.registered_models
        and player_api.registered_models["character.b3d"]
        and player_api.registered_models["character.b3d"].animations then
        local a = player_api.registered_models["character.b3d"].animations
        anims.stand = a.stand or anims.stand
        anims.walk  = a.walk  or anims.walk
        anims.sit   = a.sit   or anims.sit
        anims.lay   = a.lay   or anims.lay
    end
    return anims
end

-- Définition de l'entité NPC
local NPC_NAME = "npc_wander:npc"

local npc_def = {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.8, 0.3},
        selectionbox = {-0.3, 0.0, -0.3, 0.3, 1.8, 0.3},
        stepheight = 1.1,
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
        visual_size = {x = 1, y = 1},
        hp_max = 20, -- PV de base; la valeur par défaut des entités est 10
        makes_footstep_sound = true,
        static_save = true,
        pointable = true,
    },

    -- État interne
    _timer = 0,
    _state = "idle", -- "idle" | "walk"
    _state_left = 0,
    _yaw = 0,
    _anims = nil,
    _tex = nil,

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_acceleration({x = 0, y = GRAVITY, z = 0})
        self._anims = get_player_anims()
        self._yaw = rand_yaw()
        self.object:set_yaw(self._yaw)

        -- IMPORTANT : armure = vulnérabilité 100% au type 'fleshy' (armes/outils)
        -- Pas d'immortalité : laisse le moteur appliquer les dégâts automatiquement.
        self.object:set_armor_groups({ fleshy = 100 })

        -- Restauration textures si sauvegardées
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if type(data) == "table" and data.tex then
                self._tex = data.tex
                self.object:set_properties({textures = self._tex})
            end
        end

        -- Démarrage : idle bref puis marche
        self:_switch_state("idle")
    end,

    get_staticdata = function(self)
        return minetest.serialize({ tex = self._tex })
    end,

    -- Changement d'état + animation
    _switch_state = function(self, new_state)
        self._state = new_state
        if new_state == "walk" then
            self._state_left = math.random(WALK_MIN, WALK_MAX)
            local a = self._anims.walk
            self.object:set_animation({x = a.x, y = a.y}, a.speed or 30, 0, true)
            -- Choisit une nouvelle direction aléatoire
            self._yaw = rand_yaw()
            self.object:set_yaw(self._yaw)
        else -- idle
            self._state_left = math.random(IDLE_MIN, IDLE_MAX)
            local a = self._anims.stand
            self.object:set_animation({x = a.x, y = a.y}, a.speed or 25, 0, true)
            -- Stoppe le déplacement horizontal
            local v = self.object:get_velocity() or {x=0,y=0,z=0}
            self.object:set_velocity({x = 0, y = v.y, z = 0})
        end
    end,

    -- Détection obstacles & précipices très simple
    _blocked_or_ledge = function(self)
        local pos = self.object:get_pos()
        if not pos then return true end
        local dir = minetest.yaw_to_dir(self._yaw)
        local ahead = vector.add(pos, vector.multiply(dir, 0.6))
        -- obstacle si un des deux blocs devant (pieds/tête) est walkable
        if is_walkable({x=ahead.x, y=ahead.y + 0.1, z=ahead.z})
        or is_walkable({x=ahead.x, y=ahead.y + 1.1, z=ahead.z}) then
            return true
        end
        -- vide devant (risque de tomber) : si le bloc un peu en‑dessous n'est pas walkable
        if not is_walkable({x=ahead.x, y=ahead.y - 0.9, z=ahead.z}) then
            return true
        end
        return false
    end,

    -- PRISE DE DÉGÂTS : effets et mort
    on_punch = function(self, puncher, tflp, toolcaps, dir, damage)
        -- Laisser le moteur appliquer les dégâts (ne PAS retourner true)
        -- Ajoute juste un léger knockback et un son si disponible
        if dir then
            local kb = vector.multiply(dir, 2)
            kb.y = 2
            local v = self.object:get_velocity() or {x=0,y=0,z=0}
            self.object:set_velocity({x = v.x + kb.x, y = v.y + kb.y, z = v.z + kb.z})
        end
        minetest.sound_play("player_damage", {object = self.object, gain = 0.35, max_hear_distance = 16}, true)
    end,

    on_death = function(self, killer)
        -- Petit effet de particules à la mort
        local pos = self.object:get_pos()
        if pos then
            minetest.add_particlespawner({
                amount = 18,
                time = 0.2,
                minpos = vector.add(pos, {x=-0.2, y=0.5, z=-0.2}),
                maxpos = vector.add(pos, {x=0.2, y=1.2,  z=0.2}),
                minvel = {x=-0.5, y=0.5, z=-0.5},
                maxvel = {x= 0.5, y=1.5, z= 0.5},
                minacc = {x=0, y=-9, z=0},
                maxacc = {x=0, y=-9, z=0},
                minexptime = 0.3,
                maxexptime = 0.8,
                minsize = 1,
                maxsize = 2,
                texture = "default_item_smoke.png^[brighten",
                glow = 3,
            })
            minetest.sound_play("player_death", {pos = pos, gain = 0.6, max_hear_distance = 32}, true)
        end
    end,

    on_step = function(self, dtime, moveresult)
        self._timer = self._timer + dtime
        self._state_left = self._state_left - dtime

        if self._timer >= STEP_INTERVAL then
            self._timer = 0

            -- Changement d'état quand l'intervalle est écoulé
            if self._state_left <= 0 then
                if self._state == "idle" then
                    self:_switch_state("walk")
                else
                    self:_switch_state("idle")
                end
            end

            if self._state == "walk" then
                -- Recalcule vitesse; change de direction si bloqué
                if self:_blocked_or_ledge() then
                    -- tournez un peu et retentez
                    self._yaw = self._yaw + (math.random() * math.pi/2 - math.pi/4)
                    self.object:set_yaw(self._yaw)
                end
                local dir = minetest.yaw_to_dir(self._yaw)
                local v = self.object:get_velocity() or {x=0,y=0,z=0}
                self.object:set_velocity({x = dir.x * WALK_SPEED, y = v.y, z = dir.z * WALK_SPEED})
            end
        end
    end,
}

minetest.register_entity(NPC_NAME, npc_def)

-- Outil d'apparition (spawner) qui prend la texture du joueur placeur
minetest.register_craftitem("npc_wander:spawner", {
    description = "Spawner de NPC (texture du joueur)",
    inventory_image = "default_paper.png^[brighten^[colorize:#7ad:80",
    stack_max = 99,
    on_place = function(itemstack, placer, pointed)
        if not placer or not placer:is_player() then return itemstack end
        local pos
        if pointed and pointed.type == "node" then
            pos = pointed.above
        else
            pos = vector.add(placer:get_pos(), vector.multiply(placer:get_look_dir(), 1.5))
            pos = {x=math.floor(pos.x+0.5), y=math.floor(pos.y+0.5), z=math.floor(pos.z+0.5)}
        end
        local obj = minetest.add_entity(pos, NPC_NAME)
        if obj then
            local lua = obj:get_luaentity()
            if lua then
                lua._tex = copy_textures_from_player(placer)
                obj:set_properties({textures = lua._tex})
            end
            if not minetest.is_creative_enabled(placer:get_player_name()) then
                itemstack:take_item()
            end
        end
        return itemstack
    end
})

-- Commande /add_npc pour ajouter rapidement un PNJ devant soi
minetest.register_chatcommand("add_npc", {
    description = "Ajoute un NPC qui marche aléatoirement (texture = votre skin)",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end
        local pos = vector.add(player:get_pos(), vector.multiply(player:get_look_dir(), 1.5))
        pos.y = pos.y + 0.5
        local obj = minetest.add_entity(pos, NPC_NAME)
        if obj then
            local lua = obj:get_luaentity()
            if lua then
                lua._tex = copy_textures_from_player(player)
                obj:set_properties({textures = lua._tex})
            end
            return true, "NPC ajouté."
        end
        return false, "Échec de l'ajout du NPC."
    end
})

-----------------------------------------------------------------------
-- npc_dialog — PNJ qui marche aléatoirement + petit système de dialogue
-- Auteur : Vous + ChatGPT
-- Licence : MIT
-----------------------------------------------------------------------

local DIALOG_NPC_NAME = "npc_wander:npc_dialog"

-- Arbre de dialogue simple (modifiable)
local DEFAULT_DIALOG = {
    start = {
        text = "Salut ! Besoin de quelque chose ?",
        options = {
            {"Qui es-tu ?", "who"},
            {"Des conseils pour débuter ?", "tips"},
            {"Rien, merci. (fermer)", "bye"},
        }
    },
    who = {
        text = "Je suis un PNJ de démo. J'observe, je marche, je parle !",
        options = {
            {"Retour", "start"},
            {"Au revoir", "bye"},
        }
    },
    tips = {
        text = "Conseil rapide : fabrique quelques outils et construis un abri avant la nuit.",
        options = {
            {"Encore un conseil", "tips2"},
            {"Retour", "start"},
        }
    },
    tips2 = {
        text = "Pense à garder de la nourriture et une torche sur toi. Bon jeu !",
        options = {
            {"Retour", "start"},
            {"Au revoir", "bye"},
        }
    },
    bye = {
        text = "À plus !",
        close = true,
    }
}

-- Session de dialogue en cours par joueur
local ACTIVE_DIALOG = {} -- [playername] = { obj = ObjectRef, node = "start" }

-- Génère et affiche le formspec pour un nœud de l'arbre
local function show_dialog_formspec(pname, obj, node_id)
    local lua = obj and obj:get_luaentity()
    if not lua or not lua._dialog_tree then return end
    local node = lua._dialog_tree[node_id or "start"] or lua._dialog_tree.start
    if not node then return end

    ACTIVE_DIALOG[pname] = { obj = obj, node = node_id or "start" }

    local title = lua._dialog_title or "Dialogue"
    local text  = node.text or ""
    local opts  = node.options or {}

    local fs = {}
	fs[#fs+1] = "formspec_version[6]"
	fs[#fs+1] = "size[8,10]"
	fs[#fs+1] = ("label[0.4,0.3;%s]"):format(minetest.formspec_escape(title))
	fs[#fs+1] = ("textarea[0.4,0.8;7.2,3.6;_txt;;%s]"):format(minetest.formspec_escape(text))

	local y = 4.6
	for i, opt in ipairs(opts) do
		local btnname = ("opt%d"):format(i)
		fs[#fs+1] = ("button[0.4,%0.2f;7.2,0.9;%s;%s]")
		    :format(y, btnname, minetest.formspec_escape(opt[1]))
		y = y + 1.0
	end

    -- Bouton Fermer si pas de close explicite
    if not node.close and #opts == 0 then
        fs[#fs+1] = ("button_exit[0.4,%0.2f;7.2,0.9;_close;Fermer]"):format(y)
    end

    minetest.show_formspec(pname, "npc_wander:dialog", table.concat(fs))
end

-- ====== Helpers pour actions de dialogue ======
local function to_itemstack(spec)
    -- Accepte "default:apple 3" OU {name="default:apple", count=3, wear=0, meta={key="val"}}
    if type(spec) == "string" then
        return ItemStack(spec)
    elseif type(spec) == "table" then
        local name  = spec.name or spec[1]
        local count = tonumber(spec.count or spec[2] or 1) or 1
        local wear  = tonumber(spec.wear or 0) or 0
        if not name then return nil end
        local stack = ItemStack({name=name, count=count, wear=wear})
        if spec.meta then
            local m = stack:get_meta()
            for k,v in pairs(spec.meta) do
                m:set_string(k, tostring(v))
            end
        end
        return stack
    end
    return nil
end

local function give_item_or_drop(player, stack)
    if not player or not stack or stack:is_empty() then return "none" end
    local inv = player:get_inventory()
    if inv and inv:room_for_item("main", stack) then
        inv:add_item("main", stack)
        return "added"
    else
        local pos = player:get_pos()
        if pos then
            pos = vector.add(pos, {x=0, y=0.8, z=0})
            local obj = minetest.add_item(pos, stack)
            if obj then obj:set_velocity({x=0, y=2, z=0}) end
        end
        return "dropped"
    end
end

-- Exécute les actions (don d’objets, message…) définies sur une option
local function perform_dialog_actions(player, actions)
    if type(actions) ~= "table" then return end
    local pname = player:get_player_name()

    -- Un seul item
    if actions.give_item then
        local st = to_itemstack(actions.give_item)
        if st then
            local how = give_item_or_drop(player, st)
            if actions.msg ~= false then
                local txt = actions.msg
                    or (how == "added" and ("Tu reçois: "..st:to_string()))
                    or (how == "dropped" and ("Inventaire plein : l’objet a été déposé au sol: "..st:to_string()))
                    or nil
                if txt then minetest.chat_send_player(pname, txt) end
            end
        end
    end

    -- Plusieurs items
    if actions.give_items and type(actions.give_items) == "table" then
        for _,spec in ipairs(actions.give_items) do
            local st = to_itemstack(spec)
            if st then
                local how = give_item_or_drop(player, st)
                if actions.msg_each then
                    local txt = actions.msg_each
                        :gsub("%%ITEM%%", st:get_name())
                        :gsub("%%COUNT%%", tostring(st:get_count()))
                        :gsub("%%HOW%%", how)
                    minetest.chat_send_player(pname, txt)
                end
            end
        end
        if actions.msg then
            minetest.chat_send_player(pname, actions.msg)
        end
    end
end
-- ====== Fin helpers ======





-- Réception des choix du joueur
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "npc_wander:dialog" then return end
    local pname = player and player:get_player_name()
    local sess = pname and ACTIVE_DIALOG[pname]

    -- Fermeture (ESC ou button_exit)
    if fields and (fields.quit or fields._close) then
        if sess then ACTIVE_DIALOG[pname] = nil end
        return
    end

    if not sess or not sess.obj or not sess.obj:get_luaentity() then return end

    local lua  = sess.obj:get_luaentity()
    local tree = lua._dialog_tree or DEFAULT_DIALOG
    local cur  = tree[sess.node or "start"] or tree.start
    if not cur then return end

    -- Clic sur une option ?
    for i = 1, 12 do
        local key = "opt"..i
        if fields[key] and cur.options and cur.options[i] then
            local opt      = cur.options[i]
            local label    = opt[1]
            local jump     = opt[2]              -- soit string (id de nœud), soit table d'actions
            local actions  = nil
            local next_id  = nil
            local do_close = false

            if type(jump) == "table" then
                actions  = jump
                next_id  = jump.goto
                do_close = jump.close == true
            else
                next_id  = jump
            end

            -- Exécuter d’abord les actions (don d'objets, etc.)
            if actions then
                perform_dialog_actions(player, actions)
            end

            -- Fermer si demandé
            if do_close then
                ACTIVE_DIALOG[pname] = nil
                minetest.close_formspec(pname, "npc_wander:dialog")
                return
            end

            -- Naviguer vers un autre nœud si indiqué
            if next_id and tree[next_id] then
                ACTIVE_DIALOG[pname].node = next_id
                show_dialog_formspec(pname, sess.obj, next_id)
                return
            end

            -- Sinon, rester sur place et rafraîchir
            show_dialog_formspec(pname, sess.obj, sess.node)
            return
        end
    end
end)




-- Définition du PNJ parlant (mêmes bases que votre NPC : marche aléatoire + dégâts)
local npc_dialog_def = {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.8, 0.3},
        selectionbox = {-0.3, 0.0, -0.3, 0.3, 1.8, 0.3},
        stepheight = 1.1,
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
        visual_size = {x = 1, y = 1},
        hp_max = 20,
        makes_footstep_sound = true,
        static_save = true,
        pointable = true,
        nametag = "PNJ",
        nametag_color = "#FFFFFF",
    },

    -- État interne
    _timer = 0,
    _state = "idle",
    _state_left = 0,
    _yaw = 0,
    _anims = nil,
    _tex = nil,

    -- Dialogue
    _dialog_tree = DEFAULT_DIALOG,
    _dialog_title = "PNJ",

    on_activate = function(self, staticdata, dtime_s)
        self.object:set_acceleration({x = 0, y = GRAVITY, z = 0})
        self._anims = get_player_anims()
        self._yaw = math.random() * math.pi * 2
        self.object:set_yaw(self._yaw)
        self.object:set_armor_groups({ fleshy = 100 })

        -- Restauration textures + titre si sauvegardé
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if type(data) == "table" then
                if data.tex then
                    self._tex = data.tex
                    self.object:set_properties({textures = self._tex})
                end
                if data.title then
                    self._dialog_title = data.title
                    self.object:set_properties({nametag = data.title})
                end
            end
        end

        self:_switch_state("idle")
    end,

    get_staticdata = function(self)
        return minetest.serialize({ tex = self._tex, title = self._dialog_title })
    end,

    _switch_state = function(self, new_state)
        self._state = new_state
        if new_state == "walk" then
            self._state_left = math.random(WALK_MIN, WALK_MAX)
            local a = self._anims.walk
            self.object:set_animation({x = a.x, y = a.y}, a.speed or 30, 0, true)
            self._yaw = rand_yaw()
            self.object:set_yaw(self._yaw)
        else
            self._state_left = math.random(IDLE_MIN, IDLE_MAX)
            local a = self._anims.stand
            self.object:set_animation({x = a.x, y = a.y}, a.speed or 25, 0, true)
            local v = self.object:get_velocity() or {x=0,y=0,z=0}
            self.object:set_velocity({x = 0, y = v.y, z = 0})
        end
    end,

    _blocked_or_ledge = function(self)
        local pos = self.object:get_pos()
        if not pos then return true end
        local dir = minetest.yaw_to_dir(self._yaw)
        local ahead = vector.add(pos, vector.multiply(dir, 0.6))
        if is_walkable({x=ahead.x, y=ahead.y + 0.1, z=ahead.z})
        or is_walkable({x=ahead.x, y=ahead.y + 1.1, z=ahead.z}) then
            return true
        end
        if not is_walkable({x=ahead.x, y=ahead.y - 0.9, z=ahead.z}) then
            return true
        end
        return false
    end,

    on_punch = function(self, puncher, tflp, toolcaps, dir, damage)
        if dir then
            local kb = vector.multiply(dir, 2)
            kb.y = 2
            local v = self.object:get_velocity() or {x=0,y=0,z=0}
            self.object:set_velocity({x = v.x + kb.x, y = v.y + kb.y, z = v.z + kb.z})
        end
        minetest.sound_play("player_damage", {object = self.object, gain = 0.35, max_hear_distance = 16}, true)
    end,

    on_death = function(self, killer)
        local pos = self.object:get_pos()
        if pos then
            minetest.add_particlespawner({
                amount = 18,
                time = 0.2,
                minpos = vector.add(pos, {x=-0.2, y=0.5, z=-0.2}),
                maxpos = vector.add(pos, {x=0.2, y=1.2,  z=0.2}),
                minvel = {x=-0.5, y=0.5, z=-0.5},
                maxvel = {x= 0.5, y=1.5, z= 0.5},
                minacc = {x=0, y=-9, z=0},
                maxacc = {x=0, y=-9, z=0},
                minexptime = 0.3,
                maxexptime = 0.8,
                minsize = 1,
                maxsize = 2,
                texture = "default_item_smoke.png^[brighten",
                glow = 3,
            })
            minetest.sound_play("player_death", {pos = pos, gain = 0.6, max_hear_distance = 32}, true)
        end
        -- Nettoyage des sessions liées à cet objet
        for pname, sess in pairs(ACTIVE_DIALOG) do
            if sess.obj == self.object then
                ACTIVE_DIALOG[pname] = nil
            end
        end
    end,

    on_rightclick = function(self, clicker)
        if not clicker or not clicker:is_player() then return end
        -- Tourne vers le joueur
        local ppos = clicker:get_pos()
        local mpos = self.object:get_pos()
        if ppos and mpos then
            local dir = vector.direction(mpos, ppos)
            local yaw = minetest.dir_to_yaw(dir) + math.pi -- regarder vers le joueur
            self._yaw = yaw
            self.object:set_yaw(yaw)
        end
        show_dialog_formspec(clicker:get_player_name(), self.object, "start")
    end,

    on_step = function(self, dtime, moveresult)
        self._timer = self._timer + dtime
        self._state_left = self._state_left - dtime

        if self._timer >= STEP_INTERVAL then
            self._timer = 0
            if self._state_left <= 0 then
                if self._state == "idle" then
                    self:_switch_state("walk")
                else
                    self:_switch_state("idle")
                end
            end

            if self._state == "walk" then
                if self:_blocked_or_ledge() then
                    self._yaw = self._yaw + (math.random() * math.pi/2 - math.pi/4)
                    self.object:set_yaw(self._yaw)
                end
                local dir = minetest.yaw_to_dir(self._yaw)
                local v = self.object:get_velocity() or {x=0,y=0,z=0}
                self.object:set_velocity({x = dir.x * WALK_SPEED, y = v.y, z = dir.z * WALK_SPEED})
            end
        end
    end,
}

minetest.register_entity(DIALOG_NPC_NAME, npc_dialog_def)

-- Outil d'apparition (spawner) pour PNJ dialogué
minetest.register_craftitem("npc_wander:spawner_dialog", {
    description = "Spawner de NPC (dialogue, texture du joueur)",
    inventory_image = "default_paper.png^[brighten^[colorize:#ad7:80",
    stack_max = 99,
    on_place = function(itemstack, placer, pointed)
        if not placer or not placer:is_player() then return itemstack end
        local pos
        if pointed and pointed.type == "node" then
            pos = pointed.above
        else
            pos = vector.add(placer:get_pos(), vector.multiply(placer:get_look_dir(), 1.5))
            pos = {x=math.floor(pos.x+0.5), y=math.floor(pos.y+0.5), z=math.floor(pos.z+0.5)}
        end
        local obj = minetest.add_entity(pos, DIALOG_NPC_NAME)
        if obj then
            local lua = obj:get_luaentity()
            if lua then
                lua._tex = copy_textures_from_player(placer)
                obj:set_properties({textures = lua._tex})
                lua._dialog_title = "Habitant"
                obj:set_properties({nametag = lua._dialog_title})
            end
            if not minetest.is_creative_enabled(placer:get_player_name()) then
                itemstack:take_item()
            end
        end
        return itemstack
    end
})

-- Commande /add_npc_dialog pour ajouter rapidement un PNJ dialogué
minetest.register_chatcommand("add_npc_dialog", {
    description = "Ajoute un NPC avec petit dialogue (texture = votre skin)",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end

        -- Param optionnel : titre du PNJ (ex: /add_npc_dialog Marchand)
        local title = param and param:gsub("^%s*(.-)%s*$", "%1")
        if title == "" then title = "Habitant" end

        local pos = vector.add(player:get_pos(), vector.multiply(player:get_look_dir(), 1.5))
        pos.y = pos.y + 0.5
        local obj = minetest.add_entity(pos, DIALOG_NPC_NAME)
        if obj then
            local lua = obj:get_luaentity()
            if lua then
                lua._tex = copy_textures_from_player(player)
                obj:set_properties({textures = lua._tex})
                lua._dialog_title = title
                obj:set_properties({nametag = title})
            end
            return true, "NPC dialogué ajouté."
        end
        return false, "Échec de l'ajout du NPC."
    end
})

-----------------------------------------------------------------------
-- Chargement d'arbres de dialogue depuis un fichier .lua ou .json
-----------------------------------------------------------------------
local MODNAME = (minetest.get_current_modname and minetest.get_current_modname()) or "npc_wander"
local MODPATH = minetest.get_modpath(MODNAME)

-- Petite validation pour éviter les surprises
local function validate_dialog_tree(tree)
    if type(tree) ~= "table" or type(tree.start) ~= "table" then
        return false, "Le fichier n'a pas de table 'start'."
    end
    -- (facultatif) on pourrait vérifier que chaque option pointe vers un nœud existant
    return true
end

-- Résout un chemin: absolu / relatif au mod / par défaut dans mods/npc_wander/dialogs/
local function resolve_path(fname)
    if not fname or fname == "" then return nil end
    if fname:sub(1,1) == "/" then return fname end
    if fname:find("/") then return MODPATH .. "/" .. fname end
    return MODPATH .. "/dialogs/" .. fname
end

-- Charge un arbre via un fichier .lua qui "return { ... }"
local function load_dialog_lua(fname)
    local path = resolve_path(fname)
    if not path then return nil, "Chemin invalide" end
    local ok, t_or_err = pcall(dofile, path)
    if not ok then
        return nil, "Erreur dofile: " .. tostring(t_or_err)
    end
    if type(t_or_err) ~= "table" then
        return nil, "Le fichier .lua doit retourner une table."
    end
    local ok2, msg = validate_dialog_tree(t_or_err)
    if not ok2 then return nil, msg end
    return t_or_err
end

-- Charge un arbre via un fichier .json (nécessite un environnement insecure)
local function load_dialog_json(fname)
    local path = resolve_path(fname)
    if not path then return nil, "Chemin invalide" end

    local ie = minetest.request_insecure_environment and minetest.request_insecure_environment()
    if not ie or not ie.io then
        minetest.log("error",
            "[npc_wander] Lecture JSON impossible sans environnement insecure. " ..
            "Ajoute '"..MODNAME.."' à secure.trusted_mods dans minetest.conf, " ..
            "ou utilise un fichier .lua qui retourne la table.")
        return nil, "no_insecure_env"
    end

    local f, err = ie.io.open(path, "rb")
    if not f then return nil, "Ouverture échouée: " .. tostring(err) end
    local s = f:read("*a"); f:close()

    local t, perr = minetest.parse_json(s)
    if not t then return nil, "JSON invalide: " .. tostring(perr) end

    local ok2, msg = validate_dialog_tree(t)
    if not ok2 then return nil, msg end
    return t
end

-- /add_npc_dialog_file <lua|json> <fichier> [titre...]
minetest.register_chatcommand("add_npc_dialog_file", {
    params = "<lua|json> <fichier> [titre]",
    description = "Ajoute un PNJ dialogué avec un arbre chargé depuis un fichier .lua ou .json",
    privs = {interact = true},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Joueur introuvable." end

        local args = {}
        for w in (param or ""):gmatch("%S+") do args[#args+1] = w end
        if #args < 2 then
            return false, "Usage: /add_npc_dialog_file <lua|json> <fichier> [titre]"
        end

        local kind  = args[1]:lower()
        local file  = args[2]
        local title = (#args >= 3) and table.concat(args, " ", 3) or "Habitant"

        local tree, err
        if kind == "lua" then
            tree, err = load_dialog_lua(file)
        elseif kind == "json" then
            tree, err = load_dialog_json(file)
        else
            return false, "Type inconnu: "..kind.." (attendu: lua|json)"
        end
        if not tree then
            return false, "Échec du chargement ("..tostring(err)..")"
        end

        -- Spawn devant le joueur, comme les autres commandes
        local pos = vector.add(player:get_pos(), vector.multiply(player:get_look_dir(), 1.5))
        pos.y = pos.y + 0.5
        local obj = minetest.add_entity(pos, "npc_wander:npc_dialog")
        if not obj then
            return false, "Impossible d'ajouter le PNJ."
        end

        local lua = obj:get_luaentity()
        if lua then
            lua._tex = (copy_textures_from_player and copy_textures_from_player(player)) or {"character.png"}
            obj:set_properties({textures = lua._tex})
            lua._dialog_title = title
            lua._dialog_tree  = tree
            obj:set_properties({nametag = title})
        end

        return true, "PNJ dialogué ajouté avec l'arbre depuis '"..file.."'."
    end
})

