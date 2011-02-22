# vim: set ts=4 sw=4 et :
"""
This code converts stat data (eg: epicurves)
found in SIRCA models into data structuers that
are more easily plotted
"""
import yaml
import sets
import numpy

from stat_outputs import StatPlotData

class StatExtractor:
    """Loads epicurves into StatPlotData from a saved sirca state file"""

    def __init__(self, *args, **kwargs):
        # parsing YAML from a file
        if "file" in kwargs:
            f = file( kwargs["file"], "r" )
            self.yaml_str = f.read()
            f.close()

        # parsing YAML for a string
        elif "yaml_str" in kwargs:
            self.yaml_str = kwargs["yaml_str"]

        # already have parsed dict
        elif "stats_dict" in kwargs:
            self.stats_dict = kwargs["stats_dict"]
        else:
            raise "expected either 'file' or 'yaml_str' arguments"

    def GetStats(self):
        """Returns a list of StatPlotData objects"""
        if not hasattr(self, 'stats_dict'):
            yaml_events = yaml.parse(self.yaml_str, Loader=yaml.CLoader)
            stats_dict = self.__load_stats_dict(  yaml_events )
        else:
            stats_dict = self.stats_dict

        outputs = self.__get_stat_outputs(stats_dict)
        return outputs


    def __load_stats_dict(self, yaml_event_generator):
        """Loads a YAML document using the low-level event
        parsing method which doesn't use lots of memory and leaves
        us with the ability to filter as we load"""

        elem = None

        while True:
            event = yaml_event_generator.next()
            event_type = type(event)

            # document start
            if event_type is yaml.DocumentStartEvent:
                pass

            # stream start
            elif event_type is yaml.StreamStartEvent:
                pass

            # stream end
            elif event_type is yaml.StreamEndEvent:
                pass

            # document end
            elif event_type is yaml.DocumentEndEvent:
                return elem
            
            # mapping (ie: dictionary)
            elif event_type is yaml.MappingStartEvent:
                elem = self.__load_mapping(yaml_event_generator)

            # sequence (ie: list)
            elif event_type is yaml.SequenceStartEvent:
                elem = self.__load_sequence(yaml_event_generator)

            # scalar
            elif event_type is yaml.ScalarEvent:
                elem = event.value

            # alis (FIXME unsupported)
            elif event_type is yaml.AliasEvent:
                elem = None

            else:
                raise "event not supported: " + repr(event)
        
                
    def __load_mapping(self, yaml_event_generator):
        keyNext = True
        key = None
        dict = {}
        elem = None

        while True:
            event = yaml_event_generator.next()
            event_type = type(event)

            # mapping (ie: dictionary)
            if event_type is yaml.MappingStartEvent:
                elem = self.__load_mapping(yaml_event_generator)

            # end of map (terminate)
            elif event_type is yaml.MappingEndEvent:
                return dict

            # sequence (ie: list)
            elif event_type is yaml.SequenceStartEvent:
                elem = self.__load_sequence(yaml_event_generator)

            # scalar
            elif event_type is yaml.ScalarEvent:
                elem = event.value

            # alis (FIXME unsupported)
            elif event_type is yaml.AliasEvent:
                elem = None

            else:
                raise "event not supported: " + repr(event)
        
            if keyNext:
                key = elem
                keyNext = False
            else:
                dict[key] = elem
                keyNext = True

    def __load_sequence(self, yaml_event_generator):
        
        list = []

        while True:
            event = yaml_event_generator.next()
            event_type = type(event)

            # mapping (ie: dictionary)
            if event_type is yaml.MappingStartEvent:
                elem = self.__load_mapping(yaml_event_generator)
                list.append(elem)

            # sequence (ie: list)
            elif event_type is yaml.SequenceStartEvent:
                elem = self.__load_sequence(yaml_event_generator)
                list.append(elem)

            elif event_type is yaml.SequenceEndEvent:
                return list

            # scalar
            elif event_type is yaml.ScalarEvent:
                elem = event.value
                list.append(elem)

            # alis (FIXME unsupported)
            elif event_type is yaml.AliasEvent:
                elem = None

            else:
                raise "event not supported: " + repr(event)
        
    def __get_stat_outputs(self, doc):
        stats = doc["MODEL_STATS"]
        outputs = []

        # form each stat into a StatOutput object
        for (stat_name, stat_values) in stats.iteritems():
            (dimension_info, data_array) = self.__get_data_array(stat_values)
            outputs.append( StatPlotData(stat_name, dimension_info, data_array) )

        return outputs

    def __get_data_array(self, stats):

        # available dimensions for the data to get their range
        # and unique values
        models = sets.Set()
        states = sets.Set()
        times = sets.Set()

        data = {} # maps label to mean

        # read the data and load the dimension variables above
        for lModel in stats:
            for lTime in lModel:
                for lState in lTime:
                    if lState is not None and lState != "~":

                        label = lState["label"]
                        (model, state, time) = label.split('_')
                        
                        # strip of 't' prefix and convert to integer
                        time = int(time[1:])


                        models.add(model)
                        states.add(state)
                        times.add(time)

                        data[label] = float(lState["mean"])

        # assign each label to an index
        def assignIndices(labelSet):
            # convert to sorted lists
            labels = list(labelSet)
            labels.sort()

            # assign indices
            indices = {}
            i = 0
            for l in labels:
                indices[l] = i
                i = i + 1

            return indices
        (models, states, times) = map(assignIndices, (models, states, times) )

        # now we have something like
        # { counts : 0, densities : 1}
        # { s1 : 0, s2 : 1, s3 : 2} etc...
        #   making it easy to populate the numpy array

        # form a blank array
        # for times we include all integers in the range regardless of
        # whether there are data points for them
        dims = ( len(models), len(states), max(times) - min(times) + 1)
        array = numpy.zeros(dims, dtype=float)


        # fill the array..
        for (label, value) in data.iteritems():
            (model, state, time) = label.split('_')
            # map to indicies
            model = models[model]
            state = states[state]

            # strip of 't' and convert to int
            time = int(time[1:])
            time = time - min(times)

            array[model,state,time] = value

        # actually, don't treat time as a dimension that will be displayed
        # to the user
        return ( (models, states), array)
        

if __name__ == "__main__":
    # TEST
    docstr = """
    ---
    PARAMS: 
      A: *1334
      COORD_ARRAY: &1334 
        - -273887
        - 720964
      DENSITY: 1
      DENSITY_PCT: 0.025
      ID: -273887:720964
      X: -273887
      Y: 72096
    """

    docstr =  file('BIODIVERSE.scy').read()

    extractor = StatExtractor()
    #doc = extractor.__load_stats_dict( yaml.parse(docstr, Loader=yaml.CLoader))
    #print doc
