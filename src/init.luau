--[[
	-- LuauTypeUtils --

	v0.1.0

	A collection of various type utilities for the New Luau Type Solver.

	This software is licensed under the MIT License:
		https://github.com/Nowoshire/LuauTypeUtils/blob/main/LICENSE

		MIT License

		Copyright (c) 2026 Nowoshire

		Permission is hereby granted, free of charge, to any person obtaining a copy
		of this software and associated documentation files (the "Software"), to deal
		in the Software without restriction, including without limitation the rights
		to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
		copies of the Software, and to permit persons to whom the Software is
		furnished to do so, subject to the following conditions:

		The above copyright notice and this permission notice shall be included in all
		copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
		IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
		FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
		AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
		LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
		OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
		SOFTWARE.
]]

--!strict

--[[
	Makes all read-only or write-only properties to be both writable and readable.
]]
export type function internal(ty: type)
	const function processType(t: type)
		const tTag = t.tag
		if tTag == "table" then
			-- props
			for keyType, rwType in t:properties() do
				t:setproperty(
					keyType,
					processType(rwType.read or rwType.write :: type)
				)
			end
			
			-- indexer
			const indexer = t:indexer()
			if indexer then
				t:setindexer(
					indexer.index,
					processType(indexer.readresult)
				)
			end
		elseif tTag == "union" then
			const components = t:components()
			for i, component in components do
				components[i] = processType(component)
			end

			return types.unionof(table.unpack(components))
		elseif tTag == "intersection" then
			const components = t:components()
			for i, component in components do
				components[i] = processType(component)
			end

			return types.intersectionof(table.unpack(components))
		end

		return t
	end

	return processType(ty)
end

--[=[
--[[
	Cleanly merges two or more given tables into one, resolving conflicts by unionizing properties/indexers.
]]
type function f_mergebyunion(tyProxy: type)
	local parameters = tyProxy:parameters().head
	if not parameters then
		return types.unknown
	end
	
	const function checkTable(ty: type, argNum: number)
		local tag = ty.tag
		if tag == "table" then return end
		
		error(`mergetables<> can only be used with tables, got '{tag}' instead for argument #{argNum}`)
	end
	
	local firstTbl = parameters[1]
	if not firstTbl then
		return types.unknown
	end
	
	checkTable(firstTbl, 1)
	
	-- start iteration after the first index
	for i, tbl in next, parameters, 1 do
		checkTable(tbl, i)
		
		for keyType, rwType in tbl:properties() do
			local rType = rwType.read
			if rType then
				local existing = firstTbl:readproperty(keyType)
				
				firstTbl:setreadproperty(keyType, if existing
					then types.unionof(existing, rType)
					else rType
				)
			end
			
			local wType = rwType.write
			if wType then
				local existing = firstTbl:writeproperty(keyType) -- this GETS the write property, despite the confusing name
				
				firstTbl:setwriteproperty(keyType, if existing
					then types.unionof(existing, wType)
					else wType
				)
			end
		end
		
		-- Handle indexer
		-- Currently, different indexers for read/write are not implemented in Luau
		local indexer = tbl:readindexer()
		if not indexer then continue end
		
		local existing = firstTbl:readindexer()
		if existing then
			firstTbl:setindexer(
				types.unionof(existing.index, indexer.index),
				types.unionof(existing.result, indexer.result)
			)
		else
			firstTbl:setindexer(indexer.index, indexer.result)
		end
	end
	
	return firstTbl
end

export type mergebyunion<T...> = f_mergebyunion<(T...)->()>]=]

--[[
	Removes all nils from the given union type recursively (unions nested in tables).
]]
export type function requireddeep(ty: type)
	local opCount = 0
	const function incOpCount()
		if opCount > 10000 then
			error("Type too complex: operation limit exceeded")
		end		

		opCount += 1
	end

	const function processType(t: type)
		local tTag = t.tag
		if tTag == "table" then
			for keyType, rwType in t:properties() do
				incOpCount()
				
				t:setproperty(keyType, processType(rwType.read or rwType.write :: type))
			end
		elseif tTag == "union" then
			local components = t:components()
			for i = #components, 1, -1 do
				incOpCount()
				
				local component = components[i]
				if component:is("singleton") and component:value() == nil then
					table.remove(components, i)
				end
			end

			return types.unionof(table.unpack(components))
		end

		return t
	end

	return processType(ty) or types.singleton(nil)
end

--[[
	Returns a tabletype containing the Instance's child Instances.
]]
export type function childof(instance: type)
	local instanceTag = instance.tag
	if instanceTag ~= "extern" then
		error(`childof<type> expects an externtype, got {instanceTag} instead.`)
	end
	
	local properties = instance:properties()
	local children: {[type]: type} = {}
	
	for keyType, rwType in properties do
		-- The only property that is included in the dict is "Parent".
		-- Depending on your use case it might also be useful to include this.
		if keyType:value() == "Parent" then
			continue
		end
		
		children[keyType] = rwType.read
	end
	
	return types.newtable(children)
end

return nil