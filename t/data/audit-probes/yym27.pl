my @q = (1,2,3); my @st; push @st, shift @q while @q; unshift @q, pop @st while @st; my @z = (splice(@q, 1, 1), @q); print "@q|@z\n";
