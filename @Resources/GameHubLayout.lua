-- Pure Apps-style tile planning; all dimensions are logical pixels.
local Layout = {}
local function categoryPositions(s, compact, y, step)
    local keys = {}
    if compact and (s.favorites or 0)>0 then keys[#keys+1]='Favorites' end
    for _,key in ipairs(s.categoryKeys or {}) do keys[#keys+1]=key end
    if not s.categoryKeys then
        for i=1,(s.categories or 0) do keys[#keys+1]='RPG' end
    end
    local positions,previous,column={},nil,0
    for _,key in ipairs(keys) do
        local section=(key=='Recent' or key=='Favorites') and 'quick' or
            ((key=='Platforms' or key=='Utilities') and 'tools' or 'genres')
        if previous and section~=previous then
            if column>0 then y=y+step end
            y=y+(compact and 2 or 4); column=0
        end
        positions[#positions+1]={x=24+column*148,y=y}
        column=column+1
        if column==2 then column=0; y=y+step end
        previous=section
    end
    if column>0 then y=y+step end
    return positions,y+4
end
function Layout.plan(s)
    local favorites,categories,count=s.favorites or 0,s.categories or 0,s.count or 0
    local maximum=s.maximum or 480
    local categoryY=favorites>0 and 186 or 140
    local positions,gridY=categoryPositions(s,false,categoryY,28)
    local minimumRows=(count>0 or s.selected) and 1 or 0
    local compact=gridY+minimumRows*72+48>maximum
    local rowHeight,step,footer=72,28,48
    if compact then
        if favorites>0 then categories=categories+1 end
        categoryY,rowHeight,step,footer=88,60,24,26
        positions,gridY=categoryPositions(s,true,categoryY,step)
    end
    local rows=math.max(1,math.min(2,math.floor((maximum-gridY-footer)/rowHeight)))
    local size=rows*4
    local pages=math.max(1,math.ceil(count/size))
    local page=math.max(1,math.min(pages,math.floor(s.page or 1)))
    local bottom=gridY+math.max(minimumRows,math.ceil(math.min(count,size)/4))*rowHeight
    return {compact=compact,categoryY=categoryY,categoryStep=step,categoryPositions=positions,gridY=gridY,
        rowHeight=rowHeight,pageSize=size,page=page,pages=pages,
        first=(page-1)*size+1,last=math.min(count,page*size),
        footerY=bottom+(compact and 4 or 8),hintY=bottom+(compact and 20 or 26),height=bottom+footer}
end
return Layout
