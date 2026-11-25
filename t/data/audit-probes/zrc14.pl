sub flat { map { ref $_ ? flat(@$_) : $_ } @_ } print join(",", flat(1,[2,[3,4]],5)), "\n";
