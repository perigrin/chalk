use feature 'try'; no warnings; my $s = ""; try { $s .= "t" } catch ($e) { $s .= "c" } finally { $s .= "f" } print "$s\n";
