our @st; sub p { push @st,@_ } sub q1 { pop @st } p(1,2); my $t=q1(); p(3); print "$t@st\n";
