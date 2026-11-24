use feature 'try'; no warnings; my $s=""; try { $s.="a"; try { die "i\n" } catch ($e) { $s.="b"; die "o\n" } $s.="X" } catch ($e) { $s.="c".$e } print $s;
