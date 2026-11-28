use feature 'try'; no warnings; my $s = ""; for my $i (1..3) { try { die "z\n" if $i == 2; $s .= $i } catch ($e) { $s .= "c"; next } $s .= "." } print "$s\n";
