-- the Big Screen Layout
--
-- One (presumably bigger) window on either the left (if orientation == 1) or
-- right (if orientation == -1), with the rest of the space tiled with essentially
-- the fair algorithm of awesome.  The primary client takes up `primary_ratio` of the
-- screen.

function fair_tiles(workarea, n)
    local tiles = {}

    local rows, cols
    if n == 2 then
        rows, cols = 1, 2
    else
        rows = math.ceil(math.sqrt(n))
        cols = math.ceil(n / rows)
    end

    for i = 0, n - 1 do
        local g = {}
        local row = i % rows
        local col = math.floor(i / rows)

        local lrows, lcols
        if i >= rows * cols - rows then
            lrows = n - (rows * cols - rows)
            lcols = cols
        else
            lrows = rows
            lcols = cols
        end

        if row == lrows - 1 then
            g.height = workarea.height - math.ceil(workarea.height / lrows) * row
            g.y = workarea.height - g.height
        else
            g.height = math.ceil(workarea.height / lrows)
            g.y = g.height * row
        end

        if col == lcols - 1 then
            g.width = workarea.width - math.ceil(workarea.width / lcols) * col
            g.x = workarea.width - g.width
        else
            g.width = math.ceil(workarea.width / lcols)
            g.x = g.width * col
        end

        g.y = g.y + workarea.y
        g.x = g.x + workarea.x

        table.insert(tiles, g)
    end

    return tiles
end

function bsl_layout(p, primary_ratio, orientation)
    -- local workarea = p.workarea
    local cls = p.clients

    if #cls <= 0 then
        return
    end

    -- p.workarea is the screen, our local workarea will be either the screen size
    -- if there is only one client or the remaining screen after the primary client
    -- has been placed.
    local workarea = {
        x = p.workarea.x,
        y = p.workarea.y,
        width = p.workarea.width,
        height = p.workarea.height
    }

    if #cls == 1 then
        p.geometries[cls[1]] = workarea
        return
    end

    local function transform_x(x, width)
        if orientation == -1 then
            return p.workarea.width - x - width
        end
        return x
    end

    local function transform_geometry(g)
        return {
            x = transform_x(g.x, g.width),
            y = g.y,
            width = g.width,
            height = g.height
        }
    end

    local g_primary = {}
    local tiles, i_offset
    if primary_ratio > 0 then
        -- set the first client to take up `primary_ratio` of the screen
        g_primary.x, g_primary.y = workarea.x, workarea.y
        g_primary.width = math.floor(primary_ratio * workarea.width)
        g_primary.height = workarea.height

        workarea.x = workarea.x + g_primary.width
        workarea.width = workarea.width - g_primary.width

        -- rest of the workarea will be tiled
        tiles = fair_tiles(workarea, #cls - 1)
        i_offset = 1
    else
        -- whole workarea will be tiled
        tiles = fair_tiles(workarea, #cls)
        i_offset = 0
    end

    for i, c in ipairs(cls) do
        if i == 1 then
            if primary_ratio > 0 then
                p.geometries[c] = transform_geometry(g_primary)
            else
                p.geometries[c] = transform_geometry(tiles[i])
            end
        else
            -- if primary_ratio > 0, then tiles[1] goes to the 2nd client, i = 2
            -- otherwise tiles[1] goes to i = 1
            p.geometries[c] = transform_geometry(tiles[i - i_offset])
        end
    end
end


return function(primary_ratio, orientation)
    local orientation_str = orientation == -1 and "-rev" or ""
    return {
        name = string.format("bsl-%0.2f%s", primary_ratio, orientation_str),
        arrange = function(p)
            bsl_layout(p, primary_ratio, orientation)
        end
    }
end
