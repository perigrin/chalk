use Text::Abbrev; my %a = abbrev(qw(list load)); print join(",", sort keys %a), "\n";
