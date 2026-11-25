our $g=1; sub p { $g } my $s = join ",", map { local $g = $_; p() } 5..6; print "$s ", p(), "\n";
