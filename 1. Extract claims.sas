%LET _CLIENTTASKLABEL='Extract claims';
%LET _CLIENTPROCESSFLOWNAME='Process Flow';
%LET _CLIENTPROJECTPATH='\\pgcw01fscl03\Users$\FKU838\Documents\Projects\rxad\rxad.egp';
%LET _CLIENTPROJECTNAME='rxad.egp';
%LET _SASPROGRAMFILE=;

GOPTIONS ACCESSIBLE;
%let debug_mode = 0;
%let debug_limit = 100000;
%let class_list = RAS BBLKR CCBLKR DIURTC PPI STATIN;
%let RAS_classes = C09;
%let BBLKR_classes = C07;
%let CCBLKR_classes = C08;
%let DIURTC_classes = C03;
%let PPI_classes = A02BC;
%let STATIN_classes = C10AA C10BA C10BX;
%let study_years = 7 8 9 10 11 12 13 14 15;
%let atc_map = SH026250.NDC_ATC4_2015;
%let userlib = FKU838SL;
%let sharedlib = SH026250;
%let pdelib = IN026250;
%let pdereq = R6491;
%let proj_cn = RXAD;
%let pde_columns = PDE_ID BENE_ID SRVC_DT PROD_SRVC_ID GNN BN QTY_DSPNSD_NUM DAYS_SUPLY_NUM STR GCDF;

%macro pde_by_atcs(year_list, atcs, output, columns);
proc sql;
create table ATC_MAP_EXTRACT as
select YEAR, MONTH, NDC, ATC4
from SH026250.NDC_ATC4_2015
where
	%do a=1 %to %sysfunc(countw(&atcs));
		%if &a > 1 %then or;
		%let atc_code = %sysfunc(scan(&atcs, &a));
		substr(ATC4, 1, %length(&atc_code)) = "&atc_code"
	%end;;

create index YMN
on ATC_MAP_EXTRACT (YEAR, MONTH, NDC);
quit;

proc sql;
create table &output as
%do YN = 1 %to %sysfunc(countw(&year_list));
	%if &YN > 1 %then union all;
	%let y = %sysfunc(scan(&year_list, &YN));
	select
		%do col=1 %to %sysfunc(countw(&columns));
			%sysfunc(scan(&columns, &col)),
		%end;
		ATC4 /* Notice we inherit a comma from the %do-%end. */
		from %if &y > 11 %then &pdelib..PDE&y._&pdereq;
		%else &pdelib..PDESAF%sysfunc(putn(&y, z2.))_&pdereq; a, ATC_MAP_EXTRACT b
	where year(SRVC_DT) = YEAR and month(SRVC_DT) = MONTH and PROD_SRVC_ID = NDC
	%if &debug_mode %then and BENE_ID < &debug_limit;
%end;;

drop table ATC_MAP_EXTRACT;

create index BENE_ID
on &output (BENE_ID);
quit;
%mend;

%macro make_tables;
%do i=1 %to %sysfunc(countw(&class_list));
	%let c = %sysfunc(scan(&class_list, &i));
	%pde_by_atcs(&study_years, &&&c._classes,
		&sharedlib..&proj_cn._&c._CLMS,
		&pde_columns);
%end;
%mend;


%make_tables;

GOPTIONS NOACCESSIBLE;
%LET _CLIENTTASKLABEL=;
%LET _CLIENTPROCESSFLOWNAME=;
%LET _CLIENTPROJECTPATH=;
%LET _CLIENTPROJECTNAME=;
%LET _SASPROGRAMFILE=;

