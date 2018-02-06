#-*-perl-*-
#---------------------------------------------------------------------------
# Copyright (C) 2004-2017 Joerg Tiedemann
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#---------------------------------------------------------------------------

=head1 NAME

OPUS::Tools - a collection of tools for processing OPUS corpora

=head1 SYNOPSIS

# read bitexts (print aligned sentences to screen in readable format)
opus-read OPUS/corpus/RF/xml/en-fr.xml.gz | less

# convert an OPUS bitext to plain text (Moses) format
zcat OPUS/corpus/RF/xml/en-fr.xml.gz | opus2moses -d OPUS/corpus/RF/xml -e RF.en-fr.en -f RF.en-fr.fr

# create a multilingual corpus from the parallel RF corpus
# using 'en' as the pivot language
opus2multi OPUS/corpus/RF/xml sv de en es fr


=head1 DESCRIPTION

This is not a library but just a collection of scripts for processing/converting OPUS corpora.
Download corpus data in XML from L<http://opus.lingfil.uu.se>


=cut

package OPUS::Tools;

use strict;
use DB_File;
use Exporter 'import';

use Archive::Zip qw/ :ERROR_CODES :CONSTANTS /;
use Archive::Zip::MemberRead;


our @EXPORT = qw(set_corpus_info delete_all_corpus_info
                 find_opus_document open_opus_document
                 find_opus_documents
                 $OPUS_HOME $OPUS_CORPUS $OPUS_HTML $OPUS_DOWNLOAD);


# set OPUS home dir

my @ALT_OPUS_HOME = ( "/proj/nlpl/data/OPUS",      # taito
		      "/projects/nlpl/data/OPUS",  # abel
		      "/proj/OPUS",                # taito (old)
		      "/home/opus/OPUS" );         # lingfil

our $OPUS_HOME;
foreach (@ALT_OPUS_HOME){
    if (-d $_){
	$OPUS_HOME = $_;
	last;
    }
}

# our $OPUS_HOME     = '/proj/nlpl/data/OPUS';
our $OPUS_HTML     = $OPUS_HOME.'/html';
our $OPUS_PUBLIC   = $OPUS_HOME.'/public_html';
our $OPUS_CORPUS   = $OPUS_HOME.'/corpus';
our $OPUS_DOWNLOAD = $OPUS_HOME.'/download';
our $INFODB_HOME   = $OPUS_PUBLIC;

our $VERBOSE = 0;



## variables for info databases

my %LangNames;
my %Corpora;
my %LangPairs;
my %Bitexts;
my %Info;

my $DBOPEN = 0;

## hash of zip files (key = zipfile)
my %ZipFiles;


sub open_info_dbs{
    tie %LangNames,"DB_File","$INFODB_HOME/LangNames.db";
    tie %Corpora,"DB_File","$INFODB_HOME/Corpora.db";
    tie %LangPairs,"DB_File","$INFODB_HOME/LangPairs.db";
    tie %Bitexts,"DB_File","$INFODB_HOME/Bitexts.db";
    tie %Info,"DB_File","$INFODB_HOME/Info.db";
    $DBOPEN = 1;
}

sub close_info_dbs{
    untie %LangNames;
    untie %Corpora;
    untie %LangPairs;
    untie %Bitexts;
    untie %Info;
    $DBOPEN = 0;
}

sub set_corpus_info{
    my ($corpus,$src,$trg,$infostr) = @_;

    unless (defined $corpus && defined $src && defined $trg){
	print STDERR "specify corpus src trg";
	return 0;
    }

    &open_info_dbs unless ($DBOPEN);

    ## set corpus for source and target language
    foreach my $l ($src,$trg){
	if (exists $Corpora{$l}){
	    my @corpora = split(/\:/,$Corpora{$l});
	    unless (grep($_ eq $corpus,@corpora)){
		push(@corpora,$corpus);
		@corpora = sort @corpora;
		$Corpora{$l} = join(':',@corpora);
	    }
	}
	else{
	    $Corpora{$l} = $corpus;
	}
    }

    ## set corpus for bitext
    my $langpair = join('-',sort ($src,$trg));
    if (exists $Bitexts{$langpair}){
	my @corpora = split(/\:/,$Bitexts{$langpair});
	unless (grep($_ eq $corpus,@corpora)){
	    push(@corpora,$corpus);
	    @corpora = sort @corpora;
	    $Bitexts{$langpair} = join(':',@corpora);
	}
    }
    else{
	$Bitexts{$langpair} = $corpus;
    }


    ## set src-trg
    if (exists $LangPairs{$src}){
	my @lang = split(/\:/,$LangPairs{$src});
	unless (grep($_ eq $trg,@lang)){
	    push(@lang,$trg);
	    @lang = sort @lang;
	    $LangPairs{$src} = join(':',@lang);
	}
    }
    else{
	$LangPairs{$src} = $trg;
    }

    ## set trg-src
    if (exists $LangPairs{$trg}){
	my @lang = split(/\:/,$LangPairs{$trg});
	unless (grep($_ eq $src,@lang)){
	    push(@lang,$src);
	    @lang = sort @lang;
	    $LangPairs{$trg} = join(':',@lang);
	}
    }
    else{
	$LangPairs{$trg} = $src;
    }

    unless ($infostr){
	$infostr = read_info_files($corpus,$src,$trg);
    }

    my $key = $corpus.'/'.$langpair;
    if ($infostr){
	if ($VERBOSE){
	    if (exists $Info{$key}){
		my $info = $Info{$key};
		print STDERR "overwrite corpus info!\n";
		print STDERR "old = ",$Info{$key},"\n";
		print STDERR "new = ",$infostr,"\n";
	    }
	}
	$Info{$key} = $infostr;
    }
}


sub delete_all_corpus_info{
    my ($corpus) = @_;

    unless (defined $corpus){
	print STDERR "specify corpus src trg";
	return 0;
    }

    &open_info_dbs unless ($DBOPEN);

    foreach my $c (keys %Corpora){
	my @corpora = split(/\:/,$Corpora{$c});
	if (grep($_ eq $corpus,@corpora)){
	    @corpora = grep($_ ne $corpus,@corpora);
	    @corpora = grep($_ ne '',@corpora);
	    $Corpora{$c} = join(':',@corpora);
	}
    }

    my %src2trg=();

    foreach my $c (keys %Bitexts){
	my @corpora = split(/\:/,$Bitexts{$c});
	if (grep($_ eq $corpus,@corpora)){
	    @corpora = grep($_ ne $corpus,@corpora);
	    @corpora = grep($_ ne '',@corpora);
	    if (@corpora){
		$Bitexts{$c} = join(':',@corpora);
		my ($s,$t) = split(/\-/,$c);
		$src2trg{$s}{$t}++;
		$src2trg{$t}{$s}++;
	    }
	    else{
		delete $Bitexts{$c};
	    }
	}
	else{
	    my ($s,$t) = split(/\-/,$c);
	    $src2trg{$s}{$t}++;
	    $src2trg{$t}{$s}++;
	}
    }
    
    foreach my $l (keys %LangPairs){
	$LangPairs{$l}=join(':',sort keys %{$src2trg{$l}});
    }


    foreach my $i (keys %Info){
	my ($c,$l) = split(/\//,$i);
	if ($c eq $corpus){
	    delete $Info{$i};
	}
    }
}



sub read_info_files{
    my ($corpus,$src,$trg) = @_;

    my $CorpusXML = $OPUS_HOME.'/corpus/'.$corpus.'/xml';
    my $langpair  = join('-',sort ($src,$trg));

    my $key = $corpus.'/'.$langpair;
    my $moses = 'moses='.$key.'.txt.zip';
    my $tmx = 'tmx='.$key.'.tmx.gz';
    my $xces = 'xces='.$key.'.xml.gz:';
    $xces .= $corpus.'/'.$src.'.tar.gz:';
    $xces .= $corpus.'/'.$trg.'.tar.gz';

    my @infos = ();

    if (-e "$CorpusXML/$langpair.txt.info"){
	open F, "<$CorpusXML/$langpair.txt.info";
	my @val = <F>;
	chomp(@val);
	$moses .= ':'.join(':',@val);
	push(@infos,$moses);
    }

    if (-e "$CorpusXML/$langpair.tmx.info"){
	open F, "<$CorpusXML/$langpair.tmx.info";
	my @val = <F>;
	chomp(@val);
	$tmx .= ':'.join(':',@val);
	push(@infos,$tmx);
    }

    if (-e "$CorpusXML/$langpair.info"){
	open F, "<$CorpusXML/$langpair.info";
	my @val = <F>;
	chomp(@val);
	$xces .= ':'.join(':',@val);
	push(@infos,$xces);
    }

    return join('+',@infos);
}





## make some guesses to find a document if the path in doc does not exist
sub find_opus_document{
    my ($dir,$doc) = @_;

    return "$dir/$doc" if (-e "$dir/$doc");
    return $doc if (-e $doc);

    ## gzipped and w/o dir
    return "$doc.gz" if (-e "$doc.gz");
    return "$dir/$doc.gz" if (-e "$dir/$doc.gz");

    ## various alternatives in OPUS_CORPUS homedir
    return "$OPUS_CORPUS/$dir/$doc" if (-e "$OPUS_CORPUS/$dir/$doc");
    return "$OPUS_CORPUS/$dir/$doc.gz" if (-e "$OPUS_CORPUS/$dir/$doc.gz");
    return "$OPUS_CORPUS/$doc" if (-e "$OPUS_CORPUS/$doc");
    return "$OPUS_CORPUS/$doc.gz" if (-e "$OPUS_CORPUS/$doc.gz");
    return "$OPUS_CORPUS/$dir/xml/$doc" if (-e "$OPUS_CORPUS/$dir/xml/$doc");
    return "$OPUS_CORPUS/$dir/xml/$doc.gz" if (-e "$OPUS_CORPUS/$dir/xml/$doc.gz");
    return "$OPUS_CORPUS/$dir/raw/$doc" if (-e "$OPUS_CORPUS/$dir/raw/$doc");
    return "$OPUS_CORPUS/$dir/raw/$doc.gz" if (-e "$OPUS_CORPUS/$dir/raw/$doc.gz");

    ## try /raw/ instead of /xml/
    my $tmpdoc = $doc;
    $tmpdoc =~s/(\A|\/)xml\//${1}raw\//;
    return find_opus_document($dir,$tmpdoc) if ($doc ne $tmpdoc);

    my $tmpdir = $dir;
    $tmpdir =~s/(\A|\/)xml(\/|\Z)/${1}raw$2/;
    return find_opus_document($tmpdir,$doc) if ($dir ne $tmpdir);

    if (($doc ne $tmpdoc) && ($dir ne $tmpdir)){
	return find_opus_document($tmpdir,$tmpdoc);
    }
    return undef;
}



## open zip files and store a handle in ZipFiles
sub open_zip_file{
    my $zipfile = shift;
    if (exists $ZipFiles{$zipfile}){
	return $ZipFiles{$zipfile};
    }
    if (-e $zipfile){
	$ZipFiles{$zipfile} = Archive::Zip->new($zipfile);
	return $ZipFiles{$zipfile} if ($ZipFiles{$zipfile});
	delete $ZipFiles{$zipfile};
    }
    return undef;
}


## make some guesses to find a document if the path in doc does not exist
sub open_opus_document{
    my ($fh,$dir,$doc) = @_;

    my ($lang) = split(/\//,$doc);
    my $zip = $dir.'/'.$lang.'.zip';

    ## try to open a zip file
    my $zip = open_zip_file($dir.'/'.$lang.'.zip');
    ## also try the raw dir instead of xml-dir
    unless ($zip){
	my $rawdir = $dir;
	$rawdir=~s/(\A|\/)xml(\/|\Z)/${1}raw$2/;
    }
    $zip = open_zip_file($dir.'/'.$lang.'.zip');

    if ($zip){
	$doc =~s/\.gz$//;           # remove .gz extension
	$$fh = Archive::Zip::MemberRead->new($zip,$doc);
	return 1 if ($fh);
    }

    ## no zip file? then look for physical file
    if ($doc = find_opus_document($dir,$doc)){
	close $$fh if (defined $$fh);
	if ($doc=~/\.gz$/){
	    return open $$fh,"gzip -cd <$doc |";
	}
	else{
	    return open $$fh,"<$doc";
	}
    }
    ## no file found - try zip archives
    return 0;
}



=head1

find_opus_documents($dir,$ext[,$mindepth[,$depth]])

=cut

sub find_opus_documents{
    my $dir      = shift;
    my $ext      = shift;
    my $mindepth = shift;
    my $depth    = shift;

    my $ext = 'xml' unless (defined $ext);

    ## return files in zip files if available
    my $zip = open_zip_file($dir.'.zip');
    if ($zip){
	return $zip->memberNames(); 
    }

    my @docs=();
    if (opendir(DIR, $dir)){
	my @files = grep { /^[^\.]/ } readdir(DIR);
	closedir DIR;
	foreach my $f (@files){
	    if (-f "$dir/$f" && $f=~/\.$ext(.gz)?$/){
		if ((not defined($mindepth)) ||
		    ($depth>=$mindepth)){
		    push (@docs,"$dir/$f");
		}
	    }
	    if (-d "$dir/$f"){
		$depth++;
		push (@docs,FindDocuments("$dir/$f",$ext,$mindepth,$depth));
	    }
	}
    }
    return @docs;
}

# my @files = $zip->memberNames(); 



1;

__END__

=head1 AUTHOR

Joerg Tiedemann, L<https://bitbucket.org/tiedemann>

=head1 TODO

Better documentation in the individual scripts.

=head1 BUGS AND SUPPORT

Please report any bugs or feature requests to
L<https://bitbucket.org/tiedemann/opus-tools>.

=head1 SEE ALSO

L<http://opus.lingfil.uu.se>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Joerg Tiedemann.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.


THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut
