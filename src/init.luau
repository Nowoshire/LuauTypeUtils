--[[
	-- LuauTypeUtils --

	v0.2.0

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
type function fn_internal(ty: type)
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

export type internal<ty> = fn_internal<ty>

--[[
	Removes all nils from the given union type recursively (unions nested in tables).
]]
type function fn_requireddeep(ty: type)
	const function processType(t: type)
		const tTag = t.tag
		if tTag == "table" then
			for keyType, rwType in t:properties() do
				t:setproperty(keyType, processType(rwType.read or rwType.write :: type))
			end
		elseif tTag == "union" then
			const components = t:components()
			for i = #components, 1, -1 do
				const component = components[i]
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

export type requireddeep<ty> = fn_requireddeep<ty>

--[[
	Returns a tabletype containing the Instance's child Instances.
]]
type function fn_childof(instance: type)
	const instanceTag = instance.tag
	if instanceTag ~= "extern" then
		error(`childof<type> expects an externtype, got {instanceTag} instead.`)
	end
	
	const children: {[type]: type} = {}
	
	for keyType, rwType in instance:properties() do
		-- Depending on your use case it might also be useful to include this.
		if keyType:value() == "Parent" then continue end

		const readType = rwType.read
		if not readType or not readType:is("extern") then continue end

		-- Check for Parent to differentiate from other externtypes
		for propKeyType, propRWType in readType:properties() do
			if propKeyType:value() ~= "Parent" then continue end

			children[keyType] = readType
			break
		end
	end
	
	return types.newtable(children)
end

export type childof<instance> = fn_childof<instance>

--[[
	Returns a tabletype containing the Instance's properties, including from superclasses.
]]
type function fn_propsof(instance: type)
	const instanceTag = instance.tag
	if instanceTag ~= "extern" then
		error(`propsof<type> expects an externtype, got {instanceTag} instead.`)
	end

	const properties = {} :: {[type]: {read: type?, write: type?}}

	local parent = instance
	while parent do
		for keyType, rwType in parent:properties() do
			properties[keyType] = rwType
		end

		parent = parent:readparent()
	end

	return types.newtable(properties)
end

export type propsof<instance> = fn_propsof<instance>

return nil