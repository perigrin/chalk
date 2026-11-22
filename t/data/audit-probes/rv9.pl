use v5.42; use experimental "class"; class K { field %h = (a => 1); method m { my %c = %h; $h{b} = 2; return join(",", sort keys %c) . "|" . join(",", sort keys %h) } } print K->new->m, "\n";
