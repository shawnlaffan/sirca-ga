#  import all epicurve files in a folder and then plot them.


#load all the data
load_files = function () {
    #pattern = paste ('EPICURVE.+', type, '.+data', sep="")
    pattern = paste ('EPICURVE.+data', sep="")
    files = list.files(pattern = pattern, recursive = T)
    #files = files[grep (interact_type, files)]

    coll_data = list()
    all_data = list()
    
    lims = 1:3
    for (state in 1:3) {
        i = 1
        for (file in files[grep (paste ("_s", state, "_", sep = ""), files)]) {
            
            if (length(grep ("distance", file))) {
                interact_type = "distance"
            } else {
                interact_type = "overlap"
            }
            if (length(grep ("count", file))) {
                epi_type = "count"
            } else {
                epi_type = "density"
            }
            
            #name = paste (interact_type, basename(file))
            data = as.data.frame(t(read.csv(file, row.names=1)))
            lims[state] = max(lims[state], max(data))
            species = substr (basename(file), 1, 3)
            
            coll_label = paste (epi_type, interact_type, species, state, sep="_")
            #print (paste (file, label))
            if (is.null(coll_data[[coll_label]])) {
                coll_data[[coll_label]] = data
            }
            else {
                #print (paste(file, i))
                #  increment row names
                row.names(data) = (i*100):((i*100-1+length(row.names(data))))
                coll_data[[coll_label]] = rbind (coll_data[[coll_label]], data)
            }
            
            all_label = paste (epi_type, interact_type, basename(dirname(file)), basename(file), sep="_")
            all_data[[all_label]] = data
            
            i = i + 1
        }
    }
    
    #lims
}

#  plot the collated epi curves
plot_epi_coll_data2 {
    lims_count = c(250,   350, 1300)
    lims_dens  = c(2600, 3200, 7100)
    limvals = list ("count"   = lims_count,
                    "density" = lims_dens
                    )
    
    plot_order = c(2, 3)
    par(mfrow = plot_order)

    PLOT = F
    plotting = FALSE
    
    for (epi_type in c("count", "density")) {
        for (interact in c("distance", "overlap")) {
            i = 1
            
            #coll_names = names(coll_data)[grep (type, names(coll_data))]
    
            if (PLOT && i == 1) {
                if (plotting) {  #  turn off previous device
                    dev.off()
                }
                png (
                    paste ("collated", "_", epi_type, "_", interact, "_", type, ".png", sep=""), 
                    #units="mm", 
                    width  =  900, 
                    height = 1400, 
                    #res = 600
                )
                plotting = TRUE
                
                par(mfrow = plot_order, cex = 1.5)
            }
            
            
            for (species in list("cow", "pig")) {
                for (state in 1:3) {
                    name = paste(epi_type, interact, species, state, sep="_")
                    data = coll_data[[name]]
        
                    lims = limvals[[type]]
                    
                    #match = regexpr ('([1-9]$)', name, perl=T)
                    #start = match[[1]]
                    #end   = start +  attr(match, 'match.length') - 1
                    #state = as.numeric (substr (name, start, end))

        
                    boxplot(data,
                            #cex = cex,
                            lty = 1,
                            #main = file,
                            #boxwex = 0.5,
                            range = 0,
                            ylim = c(0, limvals[[epi_type]][state]),
                            show.names = FALSE,
                            #ylab = ylabel,
                            xlab = "time step"
                            )
                    
                    axis (1)  #  plot the axis
                    if (species == "cow") {
                        title (ylab = paste ("state", state)
                               #, cex.lab = 1
                               )
                    }
                    
                    #print (paste (name, state, epi_type, lab, i))
                    #print (colnames(data))
                    
                    if (i <= 2) {
                       title (main = species)
                    }
                    
                    i = i + 1
                }
                
            }
    
        }
    }
    

    if (plotting) {  #  turn off previous device
        dev.off()
    }
    
}

#  plot the collated epi curves
plot_epi_coll_data {
    lims_count = c(250,   350, 1300)
    lims_dens  = c(2600, 3200, 7100)
    limvals = list ("count"   = lims_count,
                    "density" = lims_dens
                    )
    
    plot_order = c(2, 3)
    par(mfrow = plot_order)

    PLOT = T
    plotting = FALSE
    
    for (epi_type in c("count", "density")) {
        for (interact in c("distance", "overlap")) {
            i = 1
            
            #coll_names = names(coll_data)[grep (type, names(coll_data))]
    
            if (PLOT && i == 1) {
                if (plotting) {  #  turn off previous device
                    dev.off()
                }
                png (
                    paste ("collated_r_", epi_type, "_", interact, ".png", sep=""), 
                    #units="mm", 
                    width  = 1400, 
                    height =  900, 
                    #res = 600
                )
                plotting = TRUE
                
                par(mfrow = plot_order, cex = 1.5)
            }
            
            
            for (species in list("cow", "pig")) {
                for (state in 1:3) {
                    name = paste(epi_type, interact, species, state, sep="_")
                    data = coll_data[[name]]
        
                    lims = limvals[[type]]
                    
                    #match = regexpr ('([1-9]$)', name, perl=T)
                    #start = match[[1]]
                    #end   = start +  attr(match, 'match.length') - 1
                    #state = as.numeric (substr (name, start, end))

        
                    boxplot(data,
                            #cex = cex,
                            lty = 1,
                            #main = file,
                            #boxwex = 0.5,
                            range = 0,
                            ylim = c(0, limvals[[epi_type]][state]),
                            show.names = FALSE,
                            #ylab = ylabel,
                            xlab = "time step"
                            )
                    
                    axis (1)  #  plot the axis
                    if (state == 1) {
                        title (ylab = species, cex.lab = 1.5, font.lab = 2)
                    }
                    
                    mod_i = i %% 6
                    if (mod_i > 0 && mod_i < 4) {
                        title (main = paste ("state", state), cex.main = 1.5)
                    }

                    i = i + 1
                }
                
            }
    
        }
    }
    

    if (plotting) {  #  turn off previous device
        dev.off()
    }
    
}

get_zero_data = function () {
    pattern = paste ('ZEROES.+', sep="")
    files = list.files(pattern = pattern, recursive = T)
    
    zero_data = list()
    
    for (file in files) {
        if (length(grep ("distance", file))) {
            interact_type = "distance"
        } else {
            interact_type = "overlap"
        }
        if (length(grep ("count", file))) {
            epi_type = "count"
        } else {
            epi_type = "density"
        }
        if (length(grep ("cow", file))) {
            animal = "cow"
        } else {
            animal = "pig"
        }
        type = paste (animal, interact_type, epi_type, sep="_")

        data = read.csv(file, row.names=1)

        if (is.null(zero_data[[type]])) {
            zero_data[[type]] = data
        } else {
            zero_data[[type]] = zero_data[[type]] + data
        }

    }
}

plot_zero_data = function () {
    #  assumes list zero_data exists
    
    #plot_order = c(2, 3)
    #par(mfrow = plot_order)
    
    cc = grep ("count", names (zero_data))
    plotted = 0
    lty = 1
    for (i in cc) {
        if (!plotted) {
            plot  (zero_data[[names(zero_data)[i]]][2:101,2], type="l", ylim=c(0,3000))
        } else {
            lines (zero_data[[names(zero_data)[i]]][2:101,2], type="l", lty=lty)
        }
        lty = lty + 1
        plotted = 1
    }
    #legend()
}


plot_epi = function (type="count") {
    
    lims_count = c(250,   350, 1300)
    lims_dens  = c(2600, 3200, 7100)
    limvals = list ("count"   = lims_count,
                    "density" = lims_dens
                    )

    plot_order = c(2, 3)
    par(mfrow = plot_order)

    PLOT = T
    plotting = FALSE
    
    for (epi_type in c("count", "density")) {
        pattern = paste ('EPICURVE.+', epi_type, '.+data.csv', sep="")
        files = list.files(pattern = pattern, recursive = T)
        
        i = 0
        for (file in files) {
            i = i + 1
            
            match = regexpr ('(?<=interact_)[a-z]+', file, perl=T)
            start = match[[1]]
            end   = start +  attr(match, 'match.length') - 1
            interact = substr (file, start, end)
    
    
            if (PLOT && i %% 6 == 1) {
                if (plotting) {  #  turn off previous device
                    dev.off()
                }
                png (
                    paste (interact, "_", epi_type, basename(dirname(file)), ".png", sep=""), 
                    #units="mm", 
                    width = 1400, 
                    height = 900, 
                    #res = 600
                )
                plotting = TRUE
                
                par(mfrow = plot_order, cex = 1.5)
            }
    
            data = t(read.csv(file, row.names=1))
            base = basename(file)
            match = regexpr ('(?<=_s)[1-9](?=_)', base, perl=T)
            start = match[[1]]
            end   = start +  attr(match, 'match.length') - 1
            state = as.numeric (substr (base, start, end))
            
            lims = limvals[[epi_type]]
    
            boxplot(data,
                    outcex = 0.7,
                    lty = 1,
                    #main = file,
                    #boxwex = 0.5,
                    range = 0,
                    ylim = c(0, lims[state]),
                    show.names=FALSE,
                    #ylab = ylabel,
                    xlab = "time step",
                    )
            
            axis (1)  #  plot the axis
            if (state == 1) {
                match = regexpr ('^[a-zA-Z]+(?=_)', base, perl=T)
                start = match[[1]]
                end   = start +  attr(match, 'match.length') - 1
                lab   = substr (base, start, end)
                title (ylab = lab, cex.lab = 1.5, font.lab = 2)
            }
            
            if ((i %% 6) < 4) {
                title (main = paste ("state", state), cex.main = 1.5)
                
            }
    
        }
        
    
        if (plotting) {  #  turn off previous device
            dev.off()
        }
        
        files
    }
    
}

