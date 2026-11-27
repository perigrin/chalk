our $s = "s"; our @s = (1); *t = *s; our ($t, @t); $t .= "t"; push @t, 2; print "$s@s\n";
