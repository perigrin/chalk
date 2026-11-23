my %h=(a=>1); my %c=%h; delete $c{a}; print exists $h{a} ? "y":"n","\n";
