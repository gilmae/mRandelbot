def generate_colour
  colour = 0

  (0..2).each { |i|
    colour = colour * 255 + (rand() * 255).to_i
  }

  return "#{"%06X" % colour}"
end

def generate_gradient
  gradient = []

  point_count = (rand() * 3 + 4).to_i

  (0..point_count).each { |i|
    gradient << ["#{"%.16f" % (1 - rand())}", generate_colour]
    gradient << ["#{"%.16f" % (1 - rand() ** 2)}", generate_colour]
    gradient << ["#{"%.16f" % (1 - rand() ** 4)}", generate_colour]
    gradient << ["#{"%.16f" % (1 - rand() ** 8)}", generate_colour]
  }

  gradient.delete_if { |p1, _| p1.to_f == 0.0 || p1.to_f == 1.0 }
  gradient = gradient.sort { |p1, p2| p1[0] <=> p2[0] }

  gradient.first[0] = "0.000"
  gradient.last[0] = "1.000"

  gradient
end
