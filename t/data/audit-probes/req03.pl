use feature "state"; sub c { state $l=[]; push @$l,1; scalar @$l } c(); print c(),"\n";
