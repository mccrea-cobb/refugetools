
#' @name import.telonics
#' @title  Import and format Telonics Iridium GPS collar data
#'
#' @description \code{import.telonics()} imports and reformats raw Telonics GPS collar data from csv file into a tidy format for visualization and analysis.
#'
#' @param iridium_csv.dir The file directory path to a folder containing Iridium csv file to reformat.
#' @param collprogsfile The file directory path and file name of an Rdat file  containing information on the file schedules of individual GPS collars.
#' @param save.file If \code{TRUE}, saves an output file.
#' @param save.name The file directory path of the output file (if \code{save.file=TRUE}).
#' @param returnx If \code{TRUE}, returns a dataframe of the output into the workspace.
#' @param pattern The pattern of the input csv file.
#'
#' @return If \code{returnx = TRUE}, returns a dataframe of GPS collar data in tidy format (flat file). If \code{save.file = TRUE}, saves the outout.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' import.telonics(iridium_csv.dir="./data/collardata",
#' collprogsfile = "./data/tcp.rda", save.file=TRUE,
#' save.name="../data/dat.Rdata", returnx=FALSE, pattern="Complete")}

## Adapted from batch.flat.gps()

import.telonics <- function(iridium_csv.dir,
                           collprogsfile,
                           save.file,
                           save.name,
                           returnx,
                           pattern){

    flat.gps <- function(myfile, collprogsfile){
        ## load required packages
        require(moveHMM)
        collprogsfile <- collprogsfile
        x <- load(collprogsfile)
        tcp <- get(x)
        levs1 = c("Resolved QFP", "Resolved QFP (Uncertain)",
                  "Unresolved QFP", "Missing") # types of GPS fixes
        nlevs1 = length(levs1)
        levs2 = c("Primary","Auxiliary 1","Auxiliary 2","Auxiliary 3") # fix-rate schedule names
        nlevs2 = length(levs2)
        levs3 = c("P","A1","A2","A3")
        levs4 = paste0(1:12,"W")
        ## read in data as text and convert to data.frame
        x = readLines(myfile)
        ctn = substr(x[8],5,nchar(x[8]))
        x = utils::read.csv(textConnection(paste0(x[-(1:23)],collapse="\n")),stringsAsFactors=FALSE)
        ## retain location data and convert to dataframe
        attr(x,"CTN") = ctn # assign CTN# as attribute
        x = cbind(rep(ctn,nrow(x)),
                  x[,c("GPS.Fix.Time","GPS.Fix.Attempt","GPS.Latitude","GPS.Longitude",
                       "GPS.UTM.Zone", "GPS.UTM.Northing", "GPS.UTM.Easting", "GPS.Altitude",
                       "Schedule.Set","GPS.Horizontal.Dilution","GPS.Satellite.Count")])
        dimnames(x)[[2]] = c("id","fixtime","fixtype","lat","lon",
                             "utmzone","utmy","utmx","alt",
                             "fixsched","hdop","nsats")
        x$fixtype[x$fixtype==""] = NA # replace empty values w/ NA
        ## Subset out location data based on desired fix rate(s)
        x = x[x$fixtype %in% levs1 & x$fixsched %in% levs2,] #exclude 'Succeeded' fix type and missing fix schedules
        x$fixtype = factor(x$fixtype,levels=levs1) # convert GPS fix type to factor
        x$fixsched = factor(x$fixsched,levels=levs2) # convert fix-rate schedule names to factor
        ## Format time variables
        x$fixtime = as.POSIXct(round(as.POSIXct(x$fixtime, tz="UTC", format="%Y.%m.%d %H:%M:%S"),"mins"))
        ## Remove duplicate fixes (added on 23112018)
        x <- x[!duplicated(x$fixtime),]
        ## Create fixrate variable
        x$fixrate <- as.numeric(tcp[tcp$CTN==ctn,levs2])[match(x$fixsched,names(tcp[tcp$CTN==ctn,levs2]))]
        ## reformat utmzone variable to factor
        x$utmzone = factor(x$utmzone, levels=levs4)
        if(nrow(x)==0){
            x = list(NULL)
        } else {
            x = split(x,cumsum(c(1,diff(x$fixrate)!=0)))
            for(i in 1:length(x)){
                names(x)[[i]] = paste0("FixPeriod",i)
                attr(x[[i]],"FixPeriod") = x[[i]]$fixrate[1]
                allft = seq(x[[i]]$fixtime[1],
                            x[[i]]$fixtime[nrow(x[[i]])],
                            by=x[[i]]$fixrate[1]*3600)
                miss = c(0,which(!allft %in% x[[i]]$fixtime))
                rownames(x[[i]]) = 1:nrow(x[[i]])
                if(length(miss)>1){
                    n = length(miss)-1
                    x[[i]] = rbind(x[[i]],data.frame(id=rep(ctn,n), fixtime=allft[miss],
                                                     fixtype=rep(levs1[5],n), lat=rep(NA,n),
                                                     lon=rep(NA,n), utmzone=rep(NA,n),
                                                     utmy=rep(NA,n), utmx=rep(NA,n),
                                                     alt=rep(NA,n),fixsched=rep(NA,n),
                                                     fixrate=rep(NA,n), hdop=rep(NA,n),
                                                     nsats=rep(NA,n)))
                    x[[i]] = x[[i]][order(x[[i]]$fixtime),]
                    rownames(x[[i]]) = 1:nrow(x[[i]])
                    ind = 1 + cumsum(is.na(x[[i]]$lat))
                    not.na = !is.na(x[[i]]$lat)
                    xlist = split(x[[i]][not.na,], ind[not.na])
                    x[[i]]$fixtype[which(is.na(x[[i]]$fixtype))] = levels(x[[i]]$fixtype)[4]
                    indz = which(is.na(x[[i]]$fixrate))
                    for(j in 1:length(indz)){
                        x[[i]]$fixrate[indz[j]] = x[[i]]$fixrate[indz[j]-1]
                        x[[i]]$fixsched[indz[j]] = x[[i]]$fixsched[indz[j]-1]
                    } #j
                } else {
                    n = 0
                } #ifelse
                x[[i]][x[[i]]$fixtype==levs1[3],c("lat","lon","utmzone","utmy","utmx","alt")] <- NA
                x[[i]] = cbind(x[[i]],
                               moveHMM::prepData(data.frame(ID=x[[i]]$id, x=x[[i]]$lon,
                                                   y=x[[i]]$lat), type="LL")[,c("step","angle")])
                x[[i]]$deploy.site = tcp[tcp$CTN==ctn,"Site"]
            } #i
        } #ifelse
        x = do.call("rbind",x)
        return(x)
    }

    ## load GPS data file names
    files = unlist(lapply(iridium_csv.dir, function(x)list.files(x, pattern, full.names=TRUE)))
    ## number of GPS data files
    nfiles = length(files)
    ## extract all CTNs
    ##fs = lengths(regmatches(files, gregexpr("/", files)))[1]
    ##ctns = substr(read.table(text=files, sep="/", as.is=TRUE)[,fs+1],1,7)
    ## process and aggregate all GPS data
    dat <- do.call("rbind", lapply(files, flat.gps, collprogsfile))
    if(save.file){save(dat, file=save.name)}
    if(returnx){return(dat)}
}
