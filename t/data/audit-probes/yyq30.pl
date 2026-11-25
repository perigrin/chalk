my $i=0; while ($i < 2) { print defined $1 ? $1 : "u"; "x$i" =~ /(\d)/; $i++ } print "\n";
