# ==Extnesion methods==
Function::getter = (name, proc)	-> Reflect.defineProperty @prototype, name, {get: proc, configurable: true}
Function::setter = (name, proc)	-> Reflect.defineProperty @prototype, name, {set: proc, configurable: true}
Map::bump	= (key, step = 1) -> @set key, (if (val = @get key)? then val + step else 1)

#.{ [Classes]
class Stat
	cache_key	= "HextechEye_cache"
	stamp_key	= cache_key + ":date"

	# --Methods goes here.
	constructor: () ->
		@ready = if @reload() then new Promise((resolve) -> resolve()) else @load()

	url2doc: (path) ->
		fetch("#{if process?.type then '' else 'http://cors.io/?'}http://www.leagueofgraphs.com" + path)
		.then (resp) -> resp.text()
		.then (html) -> (new DOMParser).parseFromString(html, "text/html")#.documentElement

	load: () ->
		@url2doc("/ru/champions/counters").then ((doc) -> # Getting page itself to parse.
			# Preinit.
			@champions = new Map
			# Main parsing loop.
			for entry in doc.querySelector(".data_table").querySelectorAll("tr") when entry = entry.querySelector "td"
				console.log entry
				@champions.set entry.querySelector("img").getAttribute("title"), data={}# Adding champ to listing.
				rec = await @url2doc entry.querySelector("a").getAttribute "href"		# Parsing recommendations page.
				for table, idx in rec.querySelectorAll(".data_table.sortable_table")	# Parsing underlying tables.
					data[['allies', 'victims', 'nemesises'][idx]] = 					# Parsing tables to three lists.
						for entry in table.querySelectorAll "tr" when entry = entry.querySelector "img" # Check & parse.
							entry.getAttribute "title"									# Register champ name.
			# Storing data for later usage.
			@cache = @json
			@stamp = Date.now()
		).bind @

	reload: () ->
		try 
			if @stamp and (Date.now() - @stamp) / (24*60*60*1000) < 3
				@json = @cache
				@champions if @champions.size

	recommend: (bans, team, foes) ->
		# Primary setup.
		recom = new Map()		
		# Adding all recommended synergies.
		for champ in team
			recom.bump(synergy) for synergy in @champions.get(champ).allies
		# Adding all recommended counters and removing nemesisi.
		for champ in foes
			recom.bump(nemesis) for nemesis in @champions.get(champ).nemesises
			recom.bump(victim,-1) for victim in @champions.get(champ).victims
		# Removing banned chars.
		recom.delete(ban) for ban in bans
		# Finalizing.
		[...recom].filter((x) -> x[1] > 0).sort((a, b) -> b[1] - a[1])[...15].map (sub) -> sub[0]
		
	# --Properties goes here.
	@getter 'cache', ()		-> localStorage.getItem(cache_key)
	@setter 'cache', (val)	-> localStorage.setItem(cache_key, val)
	@getter 'stamp', ()		-> localStorage.getItem(stamp_key)
	@setter 'stamp', (val)	-> localStorage.setItem(stamp_key, val)
	@getter 'json', ()		-> JSON.stringify [...@champions]
	@setter 'json', (val)	-> @champions = new Map JSON.parse val
# -------------------- #
class UI
	stub		= "-----"
	row_names	= ['bans', 'team', 'foes']


	# --Methods goes here.
	constructor: () ->
		# Primary setup.
		@db		= new Stat
		@db.ready.then (-> @fill()).bind @
		@out	= document.getElementById "advisor"
		@in		= {team: [], bans: [], foes: []}
		# Error handlers setup.
		window.onerror = (msg, url, ln, col, e) ->
			console.error e
			alert "#{e.toString()} !\nLine №#{ln}[#{col}], #{new URL(url).pathname}"
			return true

	fill: () ->
		# Initial setup.
		rows	= (document.getElementById row for row in row_names)
		@cache	= new Map([['',@name2option()]].concat([name,@name2option(name)] for name from @db.champions.keys()))
		# Rows filling.
		for idx in [2..20] # 4 team slots, 10 ban slots, 5 foe slots.
			sel = document.createElement("select")
			@in[row_names[factor = idx % 4 % 3]].push sel
			sel.setAttribute "class", "selector"
			sel.innerHTML	= @name2option()
			sel.style.color	= ["crimson", "cyan", "coral"][factor]
			sel.addEventListener 'change', @sync.bind @
			rows[factor].appendChild sel
		# Finalization.
		@sync()
		document.getElementById('stub').style.visibility = 'hidden'
		document.getElementById('ui').style.visibility = 'visible'

	sync: () ->
		# Initial definitions.
		fetch	= (row_name, force) => val for sel in @in[row_name] when (stub isnt val = unescape(sel.value)) or force
		# Primary loop
		for row, idx in row_names
			# Loop setup.
			pool = new Map @cache
			# Deleting entries from opposing rows.
			for counter, cidx in row_names when cidx isnt idx
				pool.delete(excl) for excl in fetch counter
			# Correcting current rows.
			for sel, pos in @in[row]
				subpool			= new Map pool
				subpool.delete(choice) for choice, scan in fetch(row, true) when scan isnt pos
				prev			= sel.value
				sel.innerHTML	= [...subpool.values()].join ''
				sel.value		= prev
		# Finalization.
		vals = @db.recommend ...(fetch(row) for row in row_names)
		@out.innerHTML = (@name2option(champ) for champ from vals).join ''

	name2option: (name = stub) ->
		"<option value='#{escape(name)}'>#{name}</option>"				
#.} [Classes]

# ==Main code==
window.ui = new UI