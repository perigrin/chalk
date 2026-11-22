sub f { my %h; $h{a} = 1; my %c = %h; $h{b} = 2; return join(",", sort keys %c) . "|" . join(",", sort keys %h) } print f(), "\n";
