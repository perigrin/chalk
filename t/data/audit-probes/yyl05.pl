for my $s (qw(a1 b c3)) { if ($s =~ /(\d)/) { print $1 } else { print defined $1 ? "d" : "u" } } print "\n";
