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
