def generate_colour
    colour =0
    

    (0..2).each { |i| 
        colour= colour * 255 + (rand()*255).to_i
    }

    return "#{'%06X' % colour}"
end

def generate_gradient
    gradient = []

    point_count = (rand() * 3 + 4).to_i

    (0..point_count).each { |i| 
        gradient << ["#{'%.6f' % rand()}", generate_colour]
    }

    gradient = gradient.sort { |p1,p2| p1[0] <=> p2[0] }

    gradient.first[0] = "0.000"
    gradient.last[0] = "1.000"

    gradient
end