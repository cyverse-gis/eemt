from subprocess import Popen, PIPE
from math import pow
import os
import re
import sys

class TiffParser(object):
    
    """This class will do following jobs:
    Read tiff file info through gdalinfo.
    Split tiff into small regions.
    """

    def __init__(self):
        
        """ Read tiff file info via gdalinfo command."""
         
        # store file name
        self.fileName = ""
        
        # coords list [upleft, lowerleft, upright, lowerright, center]
        self.projCoords = list()
        self.deciCoords = list() 
        
        # number of x and y pixels
        self.nPixelX = 0
        self.nPixelY = 0
            
    def loadTiff(self, tiffFile):
        # TODO: This print statement appears to be placeholder debugging code
        # Consider implementing proper error handling here 
        """ Read dem file info via gdalinfo command."""
        
        # store file name
        self.fileName = tiffFile.split('.tif')[0]
        
        # initialize daymetR package

        cmdInfo = ['gdalinfo', tiffFile]
        
        # Regular experssions for upper left coords extraction
        ulCoords = re.compile(r"""Upper\s+Left\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,
                             \s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        
        # Regular experssions for lower right coords extraction
        lrCoords = re.compile(r"""Lower\s+Right\s+\(\s*(\-?\d+\.\d+),\s(-?\d+\.\d+)\)\s+\(-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"W,
                             \s-?(\d+)d\s*(\d+)\'(\s?\d+\.\d+)\"N""", re.X | re.I) 
        # Execute the command
        process = Popen(cmdInfo, stdout=PIPE, shell=False)
        output, err = process.communicate()
         
        if process.returncode != 0:
            raise RuntimeError("%r failed, status code %s stdout %r stderr %r" % \
                                (cmdInfo, process.returncode, output, err))
        
        # Process gdalinfo output by lines
        output = output.split('\n')
        for i in range(len(output) - 1, -1, -1):
            if output[i].startswith("Size is"):
                # Extract # of pixels along X,Y axis
                self.nPixelX = int(output[i].split(' ')[2][:-1])
                self.nPixelY = int(output[i].split(' ')[3])
                break

            match = lrCoords.search(output[i])
            if match:
                self.projCoords.append((match.group(1), match.group(2)))
                lat = 0.0
                lon = 0.0
                # caculate lon & lat in decimal
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
                
                # upper left is three lines above
                match = ulCoords.search(output[i-3])
                self.projCoords.append((match.group(1), match.group(2)))
                lat = 0.0
                lon = 0.0
                for j in range(3):
                    lon -= float(match.group(j + 3)) / pow(60, j)
                    lat += float(match.group(j + 6)) / pow(60, j)
                self.deciCoords.append((lat, lon))
        print("PARSER")
        print(self.deciCoords)
    
    def getDecimalCoords(self):
        return self.deciCoords

    def getProjCoords(self):
        return self.projCoords

    def getName(self): 
        return self.fileName

    def split(self, size):
        
        """Split geotiff file into squares with specified size.
        sub regions will be stored in the direcotry named by the
        original geotifffile
        """
        
        # Create folder for sub regions
        directory = self.fileName.replace('.', '_')
        if not os.path.exists(directory):
            os.makedirs(directory)

        #gdal_translate -srcwin 532 206 1 1 output.idw.tif t.tif
        for i in range(self.nPixelX):
            for j in range(self.nPixelY):
                cmdTrans = ['gdal_translate','-srcwin','%d'%i, '%d'%j, '%d'%size, '%d'%size,'%s.tif' \
                            %self.fileName,'%s/%s_%d_%d.tif'%(directory, self.fileName, i, j)]
                process = Popen(cmdTrans, stdout=PIPE, shell=False)
                output, err = process.communicate()

                if process.returncode != 0:
                    raise RuntimeError("%r failed, status code %s stdout %r stderr %r" % \
                                        (cmdTrans, process.returncode, output, err))

if __name__ == '__main__':
    main()
