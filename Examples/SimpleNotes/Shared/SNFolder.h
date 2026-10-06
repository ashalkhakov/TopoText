// A folder of notes. Its properties are generated from the model as the
// target builds (Codegen: Category/Extension) into
// SNFolder+CoreDataProperties.h; this is the class they extend.

#pragma once
#import <CoreData/CoreData.h>

@class SNNote;

NS_ASSUME_NONNULL_BEGIN

@interface SNFolder : NSManagedObject
@end

NS_ASSUME_NONNULL_END

#import "SNFolder+CoreDataProperties.h"
