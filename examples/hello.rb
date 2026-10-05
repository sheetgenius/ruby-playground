# My first Ruby program!
# Lines that start with # are notes for people. The computer skips them.

puts "Hi! What's your name?"
name = gets.chomp

puts "Nice to meet you, #{name}!"
puts "Your name has #{name.length} letters."
puts "Your name backwards is #{name.reverse}."
puts "Your name SHOUTED is #{name.upcase}!!!"

puts ""
puts "What's your favorite animal?"
animal = gets.chomp

3.times do
  puts "Hooray for #{animal}!"
end

puts ""
puts "Here is a star staircase:"
1.upto(5) do |step|
  puts "*" * step
end
