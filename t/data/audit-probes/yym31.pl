my @a = (1..5)[1..3]; my @b = ('a'..'c') x 2; my @c = map { $_ * 2 } 1..3; my $s = 0; $s += $_ for 1..100; my @e = reverse 1..4; my $n = () = 1..1000; print "@a|@b|@c|$s|@e|$n\n";
