use feature 'try'; no warnings; my $s = ""; try { die "z\n" } catch ($e) { $s .= "c" } finally { $s .= "f" } print "$s\n";
