my @st; push @st,[1]; push @st,[@{$st[-1]},2]; push @{$st[0]},7; print join("|",map{"@$_"}@st),"\n";
