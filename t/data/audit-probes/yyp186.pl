our $g="ab"; sub t { $g =~ tr/a/z/ } my $s=$g; t(); print "$s$g\n";
