my $s = sprintf("%s", join ",", map { sprintf "%02d", $_ } 1..3); my $t = "Total: " . 1 + 2; { no warnings; print "$s|", $t, "|", "1" + "1", "|", "1" . "1", "\n"; }
