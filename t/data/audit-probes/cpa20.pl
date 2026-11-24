my %h=(a=>1); if ($h{a}) { my %c=%h; $c{a}=2; print "$c{a} " } print "$h{a}\n";
