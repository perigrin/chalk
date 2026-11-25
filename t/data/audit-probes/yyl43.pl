my @w = ("a1", "b22", "c"); my @n = map { /(\d+)/ ? $1 : () } @w; my @z = map { /(\d+)/ } @w; my @b = map { scalar(/(\d+)/) || 0 } @w; my @t = grep { !/\d/ } @w; print "@n|@z|@b|@t\n";
