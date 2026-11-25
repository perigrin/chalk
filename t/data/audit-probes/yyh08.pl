sub c { wantarray ? "L" : "S" } my %h = (S => 1, L => 2); my @a = ("s","l"); print $h{c()}, join("", @h{c()}), "\n";
