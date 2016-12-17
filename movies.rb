require 'sinatra'
require 'json'
require 'neo4j-core'
require 'neo4j/core/cypher_session/adaptors/http'
require 'neo4j/core/cypher_session/adaptors/bolt'
set :root, File.dirname(__FILE__)
set :public_folder, File.dirname(__FILE__) + '/static'

NEO4J_URL = ENV['NEO4J_URL'] || 'http://localhost:7474'

Neo4j::Core::CypherSession::Adaptors::Base.subscribe_to_query(&method(:puts))

# Sinatra creates a thread for each request so we create a session inside the thread as needed
def get_session
  adaptor_class = NEO4J_URL.match(/^bolt:/) ? Neo4j::Core::CypherSession::Adaptors::Bolt : Neo4j::Core::CypherSession::Adaptors::HTTP

  Neo4j::Core::CypherSession.new(adaptor_class.new(NEO4J_URL))
end

get '/' do
  send_file File.expand_path('index.html', settings.public_folder)
end

get '/graph' do
  session = get_session

  query = """
    MATCH (m:Movie)<-[:ACTED_IN]-(a:Person)
    RETURN m.title as movie, collect(a.name) as cast
    LIMIT {limit}
  """

  movies_and_casts = session.query(query, limit: params[:limit] || 50)
  nodes = []
  rels = []
  i = 0
  movies_and_casts.each do |row|
    nodes << {title: row.movie, label: 'movie'}
    target = i
    i += 1
    row.cast.each do |name|
      actor = {title: name, label: "actor"}
      source = nodes.index(actor)
      unless source
        source = i
        nodes << actor
        i+=1
      end
      rels << {source: source, target: target}
    end

  end

  {nodes: nodes, links: rels}.to_json
end

get "/search" do
  session = get_session

  query = "MATCH (movie:Movie) WHERE movie.title =~ {title} RETURN movie.title as title, movie.released as released, movie.tagline as tagline"
  response = session.query(query, title: "(?i).*#{request[:q]}.*") rescue nil
  response = session.query(query, title: "(?i).*#{request[:q]}.*")
  results = []
  response.to_a.each do |row|
    results << {
        "movie" => {
            "title" => row[:title],
            "released" => row[:released],
            "tagline" => row[:tagline]
        }
    }
  end
  results.to_json
end

get "/movie/:movie" do
  session = get_session

  query = "MATCH (movie:Movie {title:{title}}) OPTIONAL MATCH (movie)<-[r]-(person:Person) RETURN movie.title as title, collect([person.name, head(split(lower(type(r)), '_')), r.roles]) as cast LIMIT 1"
  row = session.query(query, title: params['movie']).first
  cast = []
  row[:cast].each do |c|
    cast << {
        "name" => c[0],
        "job" => c[1],
        "role" => c[2]
    }
  end
  result = {
      "title" => row[:title],
      "cast" => cast
  }
  result.to_json
end

