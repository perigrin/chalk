use feature 'try'; no warnings; my $s = ""; try { try { die "a\n" } catch ($e) { $s .= "i"; die "b\n" } } catch ($e) { $s .= "o$e" } print $s;
