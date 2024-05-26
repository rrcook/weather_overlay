defprotocol ObjectEncoder do
  @doc "Encodes the object into a bytes buffer"
  def encode(object)
end
